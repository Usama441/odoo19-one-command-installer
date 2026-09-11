# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.
from odoo import models, api


class PosOrder(models.Model):
    _inherit = 'pos.order'

    @api.model
    def _load_pos_preparation_data_fields(self):
        res = super()._load_pos_preparation_data_fields()
        return res + ['table_stand_number']

    def _send_order(self):
        super()._send_order()
        self.env['pos.prep.order'].sudo().process_order(self.id)
