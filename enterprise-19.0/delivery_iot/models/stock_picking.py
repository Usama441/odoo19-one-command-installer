# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

from random import sample

from odoo import fields, models


class StockPickingType(models.Model):
    _inherit = "stock.picking.type"

    iot_scale_ids = fields.Many2many(
        'iot.device',
        string="Scales",
        domain=[('type', '=', 'scale')],
        help="Choose the scales you want to use for this operation type. Those scales can be used to weigh the packages created."
    )
    auto_print_carrier_labels = fields.Boolean(
        "Auto Print Carrier Labels",
        help="If this checkbox is ticked, Odoo will automatically print the carrier labels of the picking when they are created. Note this requires a printer to be assigned to this report.")
    auto_print_export_documents = fields.Boolean(
        "Auto Print Export Documents",
        help="If this checkbox is ticked, Odoo will automatically print the export documents of the picking when they are created. Availability of export documents depends on the carrier and the destination. Note this requires a printer to be assigned to this report. ")


class StockPicking(models.Model):
    _inherit = "stock.picking"

    def message_post(self, **kwargs):
        message = super(StockPicking, self).message_post(**kwargs)
        report = self.env['ir.actions.report']

        for attachment in message.attachment_ids:
            if self.picking_type_id.auto_print_carrier_labels and 'Label' in attachment.name:
                print_report = report._get_report_from_name('delivery_iot.report_shipping_labels')
            elif self.picking_type_id.auto_print_export_documents and 'ShippingDoc' in attachment.name:
                print_report = report._get_report_from_name('delivery_iot.report_shipping_docs')
            else:
                continue
            self.print_attachment(print_report, attachment)
        return message

    def print_attachment(self, report, attachments):
        if report.device_ids:
            self.env['iot.channel'].send_message({
                'iot_identifiers': [report.device_ids[0].iot_id.identifier],
                'device_identifiers': [report.device_ids[0].identifier],
                'print_id': 0,
                'document': attachments.datas,
            })
