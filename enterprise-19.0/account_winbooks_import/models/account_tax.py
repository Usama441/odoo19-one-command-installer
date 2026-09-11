# Part of Odoo. See LICENSE file for full copyright and licensing details.
from odoo import models, api


class AccountTaxGroup(models.Model):
    _inherit = 'account.tax.group'

    @api.constrains('tax_payable_account_id', 'tax_receivable_account_id')
    def _check_accounts_configuration(self):
        if self.env.context.get('skip_constraints_check'):
            return
        super()._check_accounts_configuration()
