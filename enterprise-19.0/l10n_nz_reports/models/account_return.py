import datetime
from odoo import models


class AccountReturnType(models.Model):
    _inherit = 'account.return.type'

    def _get_start_date_elements(self, main_company):
        if self == self.env.ref('l10n_nz_reports.nz_tax_return_type') and main_company.account_fiscal_country_id.code == 'NZ':
            today = datetime.date.today()
            fy_dates_dict = main_company.compute_fiscalyear_dates(today)
            date_from = fy_dates_dict['date_from']
            return date_from.day, date_from.month

        return super()._get_start_date_elements(main_company)
