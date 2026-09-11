from lxml import etree
from odoo.addons.account_iso20022.tests.test_iso_variants_credit_transfer import TestSwedishIsoCreditTransfer
from odoo.tests import tagged
from odoo.tools.misc import file_path
from freezegun import freeze_time


@tagged('post_install', 'post_install_l10n', '-at_install')
class TestSwedishIsoBBANCreditTransfer(TestSwedishIsoCreditTransfer):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.swedish_partner_bank.bank_id = cls.swedish_bank

    @freeze_time('2024-03-04')
    def test_bankgiro(self):
        self.company_data['default_journal_bank'].bank_acc_number = '6543-2106'
        self.swedish_partner_bank.lock_trust_fields = False
        self.swedish_partner_bank.acc_number = '1234-5617'
        self.assertEqual(self.swedish_partner_bank.acc_type, 'bankgiro')
        batch = self.generate_iso20022_batch_payment(self.swedish_partner)
        sct_doc = self.get_sct_doc_from_batch(batch)
        xml_file_path = file_path('l10n_se_bban/tests/data/bankgiro.xml')
        expected_tree = etree.parse(xml_file_path)
        self.assertXmlTreeEqual(sct_doc, expected_tree.getroot())

    @freeze_time('2024-03-04')
    def test_plusgiro(self):
        self.company_data['default_journal_bank'].bank_acc_number = '6543-2106'
        self.swedish_partner_bank.lock_trust_fields = False
        self.swedish_partner_bank.acc_number = '543210-9'
        self.assertEqual(self.swedish_partner_bank.acc_type, 'plusgiro')
        batch = self.generate_iso20022_batch_payment(self.swedish_partner)
        sct_doc = self.get_sct_doc_from_batch(batch)
        xml_file_path = file_path('l10n_se_bban/tests/data/plusgiro.xml')
        expected_tree = etree.parse(xml_file_path)
        self.assertXmlTreeEqual(sct_doc, expected_tree.getroot())

    @freeze_time('2024-03-04')
    def test_bban(self):
        self.company_data['default_journal_bank'].bank_acc_number = '12200108451'
        self.assertEqual(self.company_data['default_journal_bank'].bank_account_id.acc_type, 'bban_se')
        self.swedish_partner_bank.lock_trust_fields = False
        self.swedish_partner_bank.acc_number = '96602675631'
        self.assertEqual(self.swedish_partner_bank.acc_type, 'bban_se')
        batch = self.generate_iso20022_batch_payment(self.swedish_partner)
        sct_doc = self.get_sct_doc_from_batch(batch)
        xml_file_path = file_path('l10n_se_bban/tests/data/bban.xml')
        expected_tree = etree.parse(xml_file_path)
        self.assertXmlTreeEqual(sct_doc, expected_tree.getroot())
