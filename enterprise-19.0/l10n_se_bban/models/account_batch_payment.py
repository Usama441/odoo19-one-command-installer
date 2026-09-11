# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import models, _
from odoo.exceptions import RedirectWarning


class AccountBatchPayment(models.Model):
    _inherit = 'account.batch.payment'

    def validate_batch(self):

        if self.payment_method_code == 'iso20022_se':
            if (
                self.journal_id.bank_account_id.acc_type in ('bban_se', 'plusgiro', 'bankgiro')
                and (no_eur_payments := self.payment_ids.filtered(lambda pay: pay.currency_id.name not in ('SEK', 'EUR')))
            ):
                raise RedirectWarning(
                    _("Internal swedish payments must be in EUR or SEK. Some payments are using another currency."),
                    no_eur_payments._get_records_action(name=_("Non-EUR/SEK Payments")),
                    _("View Payments"),
                )

            iban_payments = self.payment_ids.filtered(
                lambda pay: pay.partner_bank_id.acc_type == 'iban'
            )
            if iban_payments and iban_payments != self.payment_ids:
                raise RedirectWarning(
                    _("All payments in a batch must use either IBAN-based bank accounts or Domestic accounts (BBAN, Bankgiro or Plusgiro)."),
                    self.payment_ids._get_records_action(name=_("Mixed Payments")),
                    _("View Payments"),
                )

        return super().validate_batch()

    def _get_export_file_name_prefix(self):
        if self.payment_method_code == 'iso20022_se' and self.payment_ids and self.payment_ids[0].partner_bank_id.acc_type != 'iban':
            return "PAIN-"
        return super()._get_export_file_name_prefix()
