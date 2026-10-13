from odoo import api, fields, models


class PosOrder(models.Model):
    _inherit = "pos.order"

    it_fiscal_receipt_number = fields.Char(string="Fiscal Receipt Number")  # New format is: <receipt_number>|<printer_serial_number>
    it_fiscal_receipt_date = fields.Char(string="Fiscal Receipt Date")
    it_z_rep_number = fields.Char(string="Z-Rep Number")

    @api.model
    def read_pos_config_data(self, domain=False):
        config_ids = self.search(domain).mapped("config_id")
        return config_ids.read(['name'])
