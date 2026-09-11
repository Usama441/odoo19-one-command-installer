# Part of Odoo. See LICENSE file for full copyright and licensing details.

from lxml import etree

from odoo import api, models


class AccountJournal(models.Model):
    _inherit = "account.journal"

    @api.depends('bank_acc_number', 'company_id.account_fiscal_country_id', 'company_id.country_id')
    def _compute_sepa_pain_version(self):
        se_bban_journals = self.filtered(lambda j: j.bank_account_id.acc_type in ('bban_se', 'plusgiro', 'bankgiro'))
        # For SE BBAN, we use the pain.001.001.03 version
        se_bban_journals.sepa_pain_version = 'pain.001.001.03'
        super(AccountJournal, self - se_bban_journals)._compute_sepa_pain_version()

    def _is_se_bban(self, payment_method_code):
        return (
            payment_method_code == 'iso20022_se'
            and self.bank_account_id.acc_type in ('bban_se', 'plusgiro', 'bankgiro')
        )

    def _get_CtgyPurp(self, payment_method_code):
        if not self._is_se_bban(payment_method_code):
            return super()._get_CtgyPurp(payment_method_code)

        CtgyPurp = etree.Element('CtgyPurp')
        Cd = etree.SubElement(CtgyPurp, 'Cd')
        Cd.text = 'SALA' if self.env.context.get('sepa_payroll_sala') else 'SUPP'
        return CtgyPurp

    def _get_DbtrAcctOthr(self, payment_method_code=None):
        Othr = super()._get_DbtrAcctOthr(payment_method_code)
        if self._is_se_bban(payment_method_code):
            SchmeNm = etree.SubElement(Othr, "SchmeNm")
            Cd = etree.SubElement(SchmeNm, "Cd")
            Cd.text = 'BBAN'
        return Othr

    def _get_CdtrAcctIdOthr(self, bank_account, payment_method_code=None):
        if not self._is_se_bban(payment_method_code):
            return super()._get_CdtrAcctIdOthr(bank_account, payment_method_code)

        Othr = etree.Element("Othr")
        Id = etree.SubElement(Othr, "Id")
        Id.text = bank_account.sanitized_acc_number
        SchmeNm = etree.SubElement(Othr, "SchmeNm")
        if bank_account.acc_type == 'bankgiro':
            Prtry = etree.SubElement(SchmeNm, "Prtry")
            Prtry.text = 'BGNR'
        else:
            Cd = etree.SubElement(SchmeNm, "Cd")
            Cd.text = 'BBAN'
        return Othr

    def _get_FinInstnId(self, bank_account, payment_method_code):
        if not self._is_se_bban(payment_method_code):
            return super()._get_FinInstnId(bank_account, payment_method_code)

        FinInstnId = etree.Element("FinInstnId")
        ClrSysMmbId = etree.SubElement(FinInstnId, "ClrSysMmbId")
        ClrSysId = etree.SubElement(ClrSysMmbId, "ClrSysId")
        Cd = etree.SubElement(ClrSysId, "Cd")
        Cd.text = "SESBA"
        MmbId = etree.SubElement(ClrSysMmbId, "MmbId")
        if bank_account.acc_type == 'bankgiro':
            MmbId.text = '9900'
        elif bank_account.acc_type == 'plusgiro':
            MmbId.text = '9500'
        else:
            bank_code, _acc_num, _checksum = bank_account._se_get_acc_number_data(bank_account.acc_number)
            MmbId.text = bank_code[:4]
        return FinInstnId
