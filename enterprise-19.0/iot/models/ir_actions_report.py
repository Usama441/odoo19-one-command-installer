# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

import base64

from odoo import fields, models, _
from odoo.exceptions import UserError


class IrActionsReport(models.Model):
    _inherit = 'ir.actions.report'

    device_ids = fields.Many2many('iot.device', string='IoT Devices', domain="[('type', '=', 'printer')]",
                                help='When setting a device here, the report will be printed through this device on the IoT Box')

    def render_document(self, device_id_list, res_ids, data=None):
        """Render a document to be printed by the IoT Box through client

        :param device_id_list: The list of device ids to print the document
        :param res_ids: The list of record ids to print
        :param data: The data to pass to the report
        :return: The list of documents to print with information about the device
        """
        device_ids = self.env['iot.device'].browse(device_id_list)
        if len(device_id_list) != len(device_ids.exists()):
            raise UserError(_(
                "One of the printer used to print the document has been removed.\n"
                "To reset printers, go to the IoT App, Configuration tab, \"Reset Linked Printers\" and retry the operation."
            ))

        datas = self._render(self.report_name, res_ids, data=data)
        data_bytes = datas[0]
        data_base64 = base64.b64encode(data_bytes)
        return [{
            "iotBoxId": device.iot_id.id,
            "deviceId": device.id,
            "deviceIdentifier": device.identifier,
            "deviceName": device.display_name,
            "document": data_base64,
        } for device in device_ids]  # As it is called via JS, we format keys to camelCase

    def report_action(self, docids, data=None, config=True):
        result = super().report_action(docids, data, config)
        if result.get('type') != 'ir.actions.report':
            return result
        device = self.device_ids and self.device_ids[0]
        if data and data.get('device_id'):
            device = self.env['iot.device'].browse(data['device_id'])

        result['id'] = self.id
        result['device_ids'] = device.mapped('identifier')
        return result

    def _get_readable_fields(self):
        return super()._get_readable_fields() | {
            "device_ids",
        }

    def get_action_wizard(self, res_ids, data=None, print_id=0, selected_device_ids=None):
        wizard = self.env['select.printers.wizard'].create({
            'display_device_ids': self.device_ids,
            'device_ids': selected_device_ids
        })
        return {
                'name': "Select printers",
                'res_id': wizard.id,
                'type': 'ir.actions.act_window',
                'res_model': 'select.printers.wizard',
                'target': 'new',
                'views': [[False, 'form']],
                'context': {
                    'res_ids': res_ids,
                    'data': data,
                    'report_id': self._ids[0],
                    'print_id': print_id,
                    'default_report_id': self._ids[0]
                },
        }
