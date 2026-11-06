"""Check monitor preview safety without changing the desktop."""
import copy
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'nix/modules/desktop/shine-displays.py'
spec = importlib.util.spec_from_file_location('shine_displays', SOURCE)
displays = importlib.util.module_from_spec(spec)
spec.loader.exec_module(displays)


class ShineDisplaysTest(unittest.TestCase):
    def setUp(self):
        mode = dict(width=2560, height=1440, refresh=59951)
        self.state = dict(config_error=None, outputs=[dict(name='DP-1', id='edid:one',
            make='Example', model='Monitor', mode=mode, modes=[mode, dict(mode, refresh=143973)],
            scale=1, position=[0, 0], primary=True), dict(name='DP-2', id='edid:two',
            make='Example', model='Monitor', mode=mode, modes=[mode],
            scale=1, position=[2560, 0], primary=False)])
        self.before = copy.deepcopy(self.state)
        self.saved = False
        self.fail_save = False
        self.calls = []
        self.addCleanup(patch.stopall)
        patch.object(displays, 'control', side_effect=self.control).start()
        patch('sys.stdout', new=io.StringIO()).start()

    def control(self, action='status', **fields):
        self.calls.append((action, fields))
        if action == 'configure-outputs':
            for change in fields['outputs']:
                output = next(o for o in self.state['outputs'] if o['name'] == change['name'])
                for key, value in change.items():
                    if key == 'mode':
                        value = next(m for m in output['modes'] if displays.mode_name(m) == value)
                    output[key] = value
            # Simulate the compositor moving the adjacent monitor on scale change.
            if len(fields['outputs']) == 1:
                self.state['outputs'][1]['position'] = [1707, 0]
        if action == 'save-config':
            if self.fail_save:
                raise RuntimeError('External configuration edit')
            self.saved = True
        return copy.deepcopy(self.state)

    def preview(self, decision):
        displays.preview('DP-1', 1.5, '2560x1440@143.973', decision)

    def test_lists_exact_refresh_rates(self):
        rows = displays.display_list()
        self.assertEqual(rows[0]['mode'], '2560x1440@59.951')
        self.assertEqual(rows[0]['rates'][1]['mode'], '2560x1440@143.973')

    def test_keep_saves_after_confirmation(self):
        self.preview('keep')
        self.assertTrue(self.saved)
        self.assertEqual(self.state['outputs'][0]['scale'], 1.5)

    def test_revert_restores_both_monitors_and_does_not_save(self):
        self.preview('revert')
        self.assertEqual(self.state, self.before)
        self.assertFalse(self.saved)

    def test_timeout_and_eof_restore(self):
        for ready, text in [([], ''), ([True], '')]:
            with patch.object(displays.select, 'select', return_value=(ready, [], [])), patch('sys.stdin', io.StringIO(text)):
                self.preview(None)
            self.assertEqual(self.state, self.before)
            self.assertFalse(self.saved)

    def test_save_failure_restores(self):
        self.fail_save = True
        with self.assertRaisesRegex(RuntimeError, 'External'):
            self.preview('keep')
        self.assertEqual(self.state, self.before)

    def test_replacement_is_not_changed_on_rollback(self):
        def replace(*_):
            self.state['outputs'][0]['id'] = 'edid:replacement'
            return [], [], []
        with patch.object(displays.select, 'select', side_effect=replace):
            self.preview(None)
        changes = [fields['outputs'] for action, fields in self.calls if action == 'configure-outputs']
        self.assertEqual([o['name'] for o in changes[-1]], ['DP-2'])

    def test_invalid_scale_and_modes_never_change_outputs(self):
        for scale, mode in [(float('nan'), '2560x1440@59.951'), (2.5, '2560x1440@59.951'),
                            (1, '1920x1080@60.000'), (1, '2560x1440@144.000')]:
            with self.assertRaises(ValueError):
                displays.preview('DP-1', scale, mode, 'keep')
        self.assertFalse(any(action == 'configure-outputs' for action, _ in self.calls))

    def test_interrupt_restores(self):
        with patch.object(displays.select, 'select', side_effect=RuntimeError('interrupted')):
            with self.assertRaisesRegex(RuntimeError, 'interrupted'):
                self.preview(None)
        self.assertEqual(self.state, self.before)

    def test_partial_apply_failure_restores_the_layout(self):
        failed = False
        def apply_then_fail(action='status', **fields):
            nonlocal failed
            state = self.control(action, **fields)
            if action == 'configure-outputs' and not failed:
                failed = True
                raise RuntimeError('Mode change failed')
            return state
        with patch.object(displays, 'control', side_effect=apply_then_fail):
            with self.assertRaisesRegex(RuntimeError, 'Mode change failed'):
                self.preview('keep')
        self.assertEqual(self.state, self.before)
        self.assertFalse(self.saved)

    def test_native_rollback_resets_requested_mode_even_if_hardware_reverted(self):
        with patch.object(displays, 'wait_applied', side_effect=[RuntimeError('Rejected mode'), None, None]):
            with self.assertRaisesRegex(RuntimeError, 'Rejected mode'):
                self.preview('keep')
        changes = [fields['outputs'] for action, fields in self.calls if action == 'configure-outputs']
        self.assertEqual(changes[-1][0]['mode'], '2560x1440@59.951')
        self.assertFalse(self.saved)


if __name__ == '__main__':
    unittest.main()
