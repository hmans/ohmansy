"""Exercise output choices and rollback without touching the compositor."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'nix/modules/desktop/displays.py'
spec = importlib.util.spec_from_file_location('displays', SOURCE)
displays = importlib.util.module_from_spec(spec)
spec.loader.exec_module(displays)


class DisplaysTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'config/displays.json'
        self.output = dict(make='Example', model='Monitor', serial='demo', current_mode=0,
                           logical=dict(scale=1), modes=[
                               dict(width=2560, height=1440, refresh_rate=59951),
                               dict(width=2560, height=1440, refresh_rate=143973),
                               dict(width=1920, height=1080, refresh_rate=60000)])
        self.available = {'DP-1': self.output}
        self.calls = []
        self.fail = None
        self.addCleanup(patch.stopall)
        patch.object(displays, 'outputs', side_effect=lambda: copy.deepcopy(self.available)).start()
        patch.object(displays, 'niri', side_effect=self.niri).start()
        patch('sys.stdout', new=io.StringIO()).start()

    def niri(self, *args):
        self.calls.append(args)
        _, name, action, value = args
        if self.fail == (action, value):
            raise RuntimeError('Simulated output failure')
        output = self.available[name]
        if action == 'mode':
            output['current_mode'] = next(i for i, item in enumerate(output['modes'])
                                          if displays.mode_name(item) == value)
        else:
            output['logical']['scale'] = float(value)

    def preview(self, decision):
        displays.preview('DP-1', 1.5, '2560x1440@143.973', self.path, decision)

    def assert_restored(self):
        self.assertEqual(self.output['current_mode'], 0)
        self.assertEqual(self.output['logical']['scale'], 1)

    def test_list_filters_resolution_and_preserves_exact_rates(self):
        self.output['modes'].append(copy.deepcopy(self.output['modes'][0]))
        self.available['DP-2'] = dict(current_mode=None, logical=None)
        rows = displays.display_list()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['mode'], '2560x1440@59.951')
        self.assertEqual([row['mode'] for row in rows[0]['rates']],
                         ['2560x1440@59.951', '2560x1440@143.973'])

    def test_keep_saves_only_after_confirmation_and_preserves_other_monitors(self):
        self.path.parent.mkdir()
        self.path.write_text('{"DP-2": {"example": true}}')
        self.preview('keep')
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved['DP-1'], dict(identity=['Example', 'Monitor', 'demo'],
                                           scale=1.5, mode='2560x1440@143.973'))
        self.assertEqual(saved['DP-2'], {'example': True})
        self.assertEqual(self.output['current_mode'], 1)

    def test_revert_does_not_write_preferences(self):
        self.preview('revert')
        self.assert_restored()
        self.assertFalse(self.path.exists())

    def test_timeout_restores_settings(self):
        with patch.object(displays.select, 'select', return_value=([], [], [])):
            self.preview(None)
        self.assert_restored()

    def test_eof_restores_settings(self):
        with patch.object(displays.select, 'select', return_value=([True], [], [])), patch('sys.stdin', io.StringIO('')):
            self.preview(None)
        self.assert_restored()

    def test_partial_apply_failure_restores_both_settings(self):
        self.fail = ('scale', '1.5')
        with self.assertRaises(RuntimeError):
            self.preview('keep')
        self.assert_restored()
        self.assertFalse(self.path.exists())

    def test_save_failure_restores_runtime_settings(self):
        with patch.object(displays, 'save_preferences', side_effect=OSError('Disk full')):
            with self.assertRaises(OSError):
                self.preview('keep')
        self.assert_restored()

    def test_rejects_unsupported_modes_and_invalid_scales_before_changes(self):
        for scale, mode in [(float('nan'), '2560x1440@59.951'), (0, '2560x1440@59.951'),
                            (5, '2560x1440@59.951'), (1, '1920x1080@60.000'),
                            (1, '2560x1440@144.000')]:
            with self.assertRaises(ValueError):
                displays.preview('DP-1', scale, mode, self.path, 'keep')
        self.assertEqual(self.calls, [])

    def test_disconnect_before_apply(self):
        self.available.clear()
        with self.assertRaises(ValueError):
            self.preview('keep')
        self.assertEqual(self.calls, [])

    def test_replacement_display_is_not_overwritten_on_rollback(self):
        def disconnect(*_):
            self.output['serial'] = 'replacement'
            return [], [], []
        with patch.object(displays.select, 'select', side_effect=disconnect):
            self.preview(None)
        self.assertEqual(len(self.calls), 2)

    def test_rejected_hardware_settings_are_not_saved(self):
        with patch.object(displays, 'apply'):
            with self.assertRaises(ValueError):
                self.preview('keep')
        self.assertFalse(self.path.exists())

    def test_restore_skips_unplugged_and_replaced_monitors(self):
        self.path.parent.mkdir()
        self.path.write_text(json.dumps({
            'DP-1': dict(identity=['Example', 'Monitor', 'other'], scale=2, mode='2560x1440@59.951'),
            'DP-2': dict(identity=['Example', 'Monitor', 'demo'], scale=2, mode='2560x1440@59.951')}))
        displays.restore(self.path)
        self.assertEqual(self.calls, [])

    def test_restore_saved_choice(self):
        self.preview('keep')
        self.output['current_mode'] = 0
        self.output['logical']['scale'] = 1
        displays.restore(self.path)
        self.assertEqual(self.output['current_mode'], 1)
        self.assertEqual(self.output['logical']['scale'], 1.5)


if __name__ == '__main__':
    unittest.main()
