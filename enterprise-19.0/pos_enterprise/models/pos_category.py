from odoo import models, api


class PosCategory(models.Model):
    _inherit = "pos.category"

    @api.model
    def _load_pos_preparation_data_domain(self, data):
        # Load every category to reduce code complexity.
        return []

    @api.model
    def _load_pos_preparation_data_fields(self):
        return ['display_name']
