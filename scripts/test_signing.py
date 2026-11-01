import unittest
from signing import choose_identity


class SigningTests(unittest.TestCase):
    def test_selects_development_identity_not_distribution(self):
        output = ('1) ' + 'A' * 40 + ' "Developer ID Application: Example"\n'
                  '2) ' + 'B' * 40 + ' "Apple Development: Example"\n')
        self.assertEqual(choose_identity(output), 'B' * 40)

    def test_ambiguous_identity_requires_explicit_choice(self):
        output = ('1) ' + 'A' * 40 + ' "Apple Development: One"\n'
                  '2) ' + 'B' * 40 + ' "Apple Development: Two"\n')
        self.assertEqual(choose_identity(output), '-')
        self.assertEqual(choose_identity(output, 'chosen identity'), 'chosen identity')

    def test_no_identity_falls_back_to_ad_hoc(self):
        self.assertEqual(choose_identity('0 valid identities found'), '-')


if __name__ == '__main__':
    unittest.main()
