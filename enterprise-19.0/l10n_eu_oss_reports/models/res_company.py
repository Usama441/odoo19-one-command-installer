# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import models, fields


class ResCompany(models.Model):
    _inherit = 'res.company'

    voes = fields.Char(string="VOES Number", help="Used for companies outside EU that want to make use of OSS")
    ioss = fields.Char(string="IOSS Number", help="Identification number for companies that import goods and services into the EU. For use in OSS reports.")
    intermediary_no = fields.Char(string="Intermediary Number", help="Used for companies outside EU that import into the EU via an intermediary for OSS taxes")

    def _map_eu_taxes(self):
        super()._map_eu_taxes()
        self.env['account.return.type']._generate_or_refresh_all_returns(self.root_id)
