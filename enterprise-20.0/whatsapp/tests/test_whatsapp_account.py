from odoo.addons.whatsapp.tests.common import WhatsAppCommon


class TestWhatsAppAccount(WhatsAppCommon):

    def test_compute_callback_url(self):
        callback_url_1 = self.whatsapp_account.get_base_url() + '/whatsapp/webhook'
        callback_url_2 = self.whatsapp_account_2.get_base_url() + '/whatsapp/webhook'
        self.assertRecordValues(
            self.whatsapp_account | self.whatsapp_account_2,
            [
                {'callback_url': callback_url_1},
                {'callback_url': callback_url_2},
            ],
        )
