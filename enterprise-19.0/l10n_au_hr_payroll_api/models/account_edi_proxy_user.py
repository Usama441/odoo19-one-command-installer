# Part of Odoo. See LICENSE file for full copyright and licensing details.

import logging

from werkzeug.urls import url_join

from odoo import _, fields, models, tools, modules
from odoo.addons.account_edi_proxy_client.models.account_edi_proxy_user import AccountEdiProxyError
from odoo.exceptions import UserError
from ..exceptions import _l10n_au_raise_user_error

_logger = logging.getLogger(__name__)

DEFAULT_TEST_URL = 'http://127.0.0.1:8070'
DEFAULT_PROD_URL = 'http://127.0.0.1:8071'


class AccountEdiProxyClientUser(models.Model):
    _inherit = 'account_edi_proxy_client.user'

    proxy_type = fields.Selection(selection_add=[('l10n_au_payroll', 'Australian Payroll')], ondelete={'l10n_au_payroll': 'cascade'})

    def _get_proxy_urls(self):
        urls = super()._get_proxy_urls()
        urls['l10n_au_payroll'] = {
            'demo': False,
            'prod': self.env['ir.config_parameter'].get_param('l10n_au_payroll_iap.endpoint', DEFAULT_PROD_URL),
            'test': self.env['ir.config_parameter'].get_param('l10n_au_payroll_iap.test_endpoint', DEFAULT_TEST_URL),
        }
        return urls

    def _get_proxy_identification(self, company, proxy_type):
        if proxy_type == 'l10n_au_payroll':
            if not company.vat:
                raise UserError(_('Please fill the ABN of company "%(company_name)s" before enabling Australian Payroll Integration.',
                                  company_name=company.display_name))
            return f"{company.vat}:{company.name}"
        return super()._get_proxy_identification(company, proxy_type)

    # ----------------
    # Business methods
    # ----------------

    def _l10n_au_payroll_request(self, endpoint, params=None, handle_errors=True):
        if tools.config['test_enable'] or modules.module.current_test:
            raise UserError(_("Superchoice API Connection disabled in testing environment."))
        self.ensure_one()
        if not params:
            params = {}
        params.update(
             {
                "db_uuid": self.env['ir.config_parameter'].get_param('database.uuid'),
                "company_id": self.company_id.id,
                "client_bms_id": self.company_id.l10n_au_bms_id,
                "company_name": self.company_id.name,
                "company_abn": self.company_id.vat,
                "registration_mode": self.edi_mode,
            },
        )
        _logger.info({"endpoint": endpoint})
        try:
            response = self._make_request(
                url=url_join(self._get_server_url(), "/api/l10n_au_payroll/1" + endpoint),
                params=params,
            )
        except AccountEdiProxyError as _error:
            # Request error while contacting the IAP server. We assume it is a temporary error.
            raise _l10n_au_raise_user_error(_("Failed to contact the Australian Payroll service. Please try again later. %s", _error))

        if response.get("expired", False):
            registration = self.env["l10n_au.employer.registration"].search([
                ("company_id", "=", self.company_id.id),
                ("status", "=", "registered"),
            ])
            # Allow commiting the status change even if the main transaction is rolled back
            with self.env.registry.cursor() as new_cr:
                registration = registration.with_env(self.env(cr=new_cr))
                registration.sudo().status = "expired"

        if handle_errors and "error" in response:
            raise UserError(response["error"])
        return response
