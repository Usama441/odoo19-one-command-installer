import datetime
from freezegun import freeze_time
from unittest.mock import patch

from odoo.addons.l10n_be_codabox.tests.common import TestCodaboxCommon
from odoo.tests import tagged


@tagged('post_install_l10n', 'post_install', '-at_install')
class TestCodabox(TestCodaboxCommon):

    _test_user_groups = None  # FIXME list needed groups

    @patch('odoo.addons.l10n_be_codabox.models.account_journal.AccountJournal._l10n_be_codabox_fetch_transactions_from_iap')
    def test_codabox_file_import(self, patched_l10n_be_codabox_fetch_transactions_from_iap):
        patched_l10n_be_codabox_fetch_transactions_from_iap.return_value = [(self.coda_file_b64, '')]
        self.env.company.l10n_be_codabox_is_connected = True
        self.env['account.journal']._l10n_be_codabox_fetch_coda_transactions(self.env.company)
        imported_statement = self.env['account.bank.statement'].search([('company_id', '=', self.env.company.id)])
        self.assertRecordValues(imported_statement, [{
            'balance_start': 11812.70,
            'balance_end_real': 13646.05,
        }])

    @patch('odoo.addons.l10n_be_codabox.models.account_journal.AccountJournal._l10n_be_codabox_fetch_transactions_from_iap')
    def test_codabox_multi_accounts(self, patched_l10n_be_codabox_fetch_transactions_from_iap):
        patched_l10n_be_codabox_fetch_transactions_from_iap.return_value = [(self.coda_file_multi_accounts_b64, '')]
        self.env.company.l10n_be_codabox_is_connected = True
        self.env['account.journal']._l10n_be_codabox_fetch_coda_transactions(self.env.company)
        imported_statement = self.env['account.bank.statement'].search([('company_id', '=', self.env.company.id)])
        self.assertEqual(
            imported_statement.journal_id,
            self.bank_journal_1 + self.bank_journal_2,
        )

    @patch('odoo.addons.l10n_be_codabox.models.account_journal.AccountJournal._l10n_be_codabox_fetch_transactions_from_iap')
    def test_codabox_multi_accounts_extension(self, patched_l10n_be_codabox_fetch_transactions_from_iap):
        bank_journal_extension = self.bank_journal_1.copy(default={'extension_number': '088', 'bank_account_number': 'BE33737018595246'})
        patched_l10n_be_codabox_fetch_transactions_from_iap.return_value = [(self.coda_file_multi_accounts_extension_b64, '')]
        self.env.company.l10n_be_codabox_is_connected = True
        self.env['account.journal']._l10n_be_codabox_fetch_coda_transactions(self.env.company)
        imported_statement = self.env['account.bank.statement'].search([('company_id', '=', self.env.company.id)])
        self.assertEqual(
            imported_statement.journal_id,
            self.bank_journal_1 + bank_journal_extension,
        )

    def test_sodabox_fetch_date_import(self):
        """ Test the fetch date when we query new soda files."""
        company = self.env.company
        soda_journal = self.env['account.journal'].create({
            'name': "SODA journal",
            'type': 'general',
            'code': "SOD",
        })
        company.l10n_be_codabox_soda_journal = soda_journal
        with freeze_time('2024-01-01'):
            self.env.cr._now = datetime.datetime.now()
            self.env['account.move'].create({
                    'journal_id': soda_journal.id,
                    'date': '2024-01-01',
                    'move_type': 'entry'
            })
        with patch.object(self.env.registry['account.journal'], '_l10n_be_codabox_fetch_transactions_from_iap', return_value=[]) as patched_fetch:
            company.user_fiscalyear_lock_date = '2025-12-31'
            self.env['account.journal']._l10n_be_codabox_fetch_soda_transactions(company)
            self.assertEqual(patched_fetch.call_args.args[3], '2025-12-31')
            company.user_fiscalyear_lock_date = '0001-01-01'
            self.env['account.journal']._l10n_be_codabox_fetch_soda_transactions(company)
            self.assertEqual(patched_fetch.call_args.args[3], '2024-01-01')
