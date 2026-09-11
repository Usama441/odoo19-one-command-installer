# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import models


class L10n_Be_ReportsVatPayWizard(models.TransientModel):
    _name = 'l10n_be_reports.vat.pay.wizard'
    _inherit = ['qr.code.payment.wizard']
    _description = "Payment instructions for VAT"

    def _generate_communication(self):
        ''' Taken from https://finances.belgium.be/fr/communication-structuree
        '''
        vat = (self.company_id.vat or '').replace("BE", "")
        communication = ''
        if len(vat) == 10:
            number = int(vat)
            suffix = f"{number % 97 or 97:02}"
            communication = f"+++{vat[:3]}/{vat[3:7]}/{vat[7:]}{suffix}+++"
        return communication

    def action_send_email_instructions(self):
        self.ensure_one()
        template = self.env.ref('l10n_be_reports.email_template_vat_payment_instructions', raise_if_not_found=False)
        return self.return_id.action_send_email_instructions(self, template)
