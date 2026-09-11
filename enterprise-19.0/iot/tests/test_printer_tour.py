import json
from odoo import tests
from odoo.tests import HttpCase
from unittest.mock import patch

from odoo.addons.iot.models.iot_channel import IotChannel


@tests.tagged('post_install', '-at_install', 'iot_device_test_printer')
class TestUi(HttpCase):
    iot_websocket_messages = []

    def setUp(self):
        super().setUp()
        original_send_message = IotChannel.send_message

        self.test_iot_box = self.env['iot.box'].create({
            'name': 'Shop',
            'identifier': 'test_iot_box',
            'ip': '10.10.10.10',
            'version': '25.07',
        })

        self.test_iot_printer = self.env['iot.device'].create({
            'name': 'Receipt Printer',
            'identifier': 'printer_identifier',
            'iot_id': self.test_iot_box.id,
            'type': 'printer',
            'subtype': 'receipt_printer',
            'connection': 'network',
            'connected_status': 'connected',
        })

        def mock_send_message(iot_channel_record, message, message_type='iot_action'):
            self.iot_websocket_messages.append({message_type: message})
            if message_type == 'iot_action':
                # call the websocket response controller to simulate the response from the IoT Box
                return self.url_open(
                    '/iot/box/send_websocket',
                    headers={'Content-Type': 'application/json'},
                    data=json.dumps({
                        'params': {
                            'session_id': message['session_id'],
                            'iot_box_identifier': self.test_iot_box.identifier,
                            'device_identifier': self.test_iot_printer.identifier,
                            'status': 'connected',
                        },
                    }),
                )
            return original_send_message(iot_channel_record, message, message_type)

        mock_send_message._api_model = True

        patcher = patch.object(IotChannel, 'send_message', mock_send_message)
        self.addCleanup(patcher.stop)
        patcher.start()

    def test_iot_device_test_button(self):
        """Make sure we can use the websocket to test printers using the 'Test'
        button on the printer (iot.device) record."""
        self.start_tour("/odoo/iot", "iot_device_test_printer", login="admin")
        self.assertEqual(
            len(self.iot_websocket_messages),
            3,
            (
                "`iot.channel.send_message` should be called exactly three times: "
                "webrtc offer, websocket action, then operation confirmation."
                "This time, we received %s" % [next(iter(message.keys())) for message in self.iot_websocket_messages]
            ),
        )
        self.assertIn(
            'webrtc_offer', self.iot_websocket_messages[0], "First ws message should be of type 'webrtc_offer'."
        )
        self.assertIn(
            'iot_action', self.iot_websocket_messages[1], "Second ws message should be of type 'iot_action'."
        )
