# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.
import datetime
from dateutil.relativedelta import relativedelta


from odoo import fields, models


class AccountFinancialYearOp(models.TransientModel):
    _inherit = 'account.financial.year.op'
    _description = 'Opening Balance of Financial Year'

    account_return_periodicity = fields.Selection(related='company_id.account_return_periodicity', string='Periodicity in month', readonly=False, required=True)
    account_tax_return_journal_id = fields.Many2one(related='company_id.account_tax_return_journal_id', string='Journal', readonly=False)
    account_return_reminder_day = fields.Integer(related='company_id.account_return_reminder_day', string='Reminder', readonly=False, required=True)
    vat_label = fields.Char(related="company_id.country_id.vat_label")

    def action_save_onboarding_fiscal_year(self):
        result_action = super().action_save_onboarding_fiscal_year()

        self.env['account.return.type'].with_context(
            forced_date_from=self.opening_date,
            forced_date_to=datetime.date.today() + relativedelta(years=1),
        )._generate_or_refresh_all_returns(self.company_id)
        if self.env.context.get('open_account_return_on_save'):
            return self.env['account.return'].action_open_tax_return_view()

        return result_action
