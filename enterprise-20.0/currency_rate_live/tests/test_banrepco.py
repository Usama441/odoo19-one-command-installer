from datetime import date
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged


def trm_response(published_for, trm):
    return b"""<?xml version="1.0" encoding="UTF-8"?>
<GenericData xmlns="http://www.sdmx.org/resources/sdmxml/schemas/v2_1/message"
             xmlns:g="http://www.sdmx.org/resources/sdmxml/schemas/v2_1/data/generic">
  <DataSet>
    <g:Series>
      <g:Obs>
        <g:ObsDimension value="%s"/>
        <g:ObsValue value="%s"/>
      </g:Obs>
    </g:Series>
  </DataSet>
</GenericData>
""" % (published_for.strftime('%Y%m%d').encode(), str(trm).encode())


@tagged('post_install', '-at_install')
class TestBanrepco(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.cop = cls.env.ref('base.COP')
        cls.usd = cls.env.ref('base.USD')
        (cls.cop + cls.usd).active = True
        cls.company = cls.env['res.company'].create({
            'name': 'Test CO',
            'currency_id': cls.cop.id,
            'currency_provider': 'banrepco',
        })

    def fetch(self, published_for, trm):
        class Response:
            content = trm_response(published_for, trm)

            def raise_for_status(self):
                pass

        with patch('odoo.addons.currency_rate_live.models.res_config_settings.requests.get',
                   return_value=Response()):
            self.company.update_currency_rates()

    def test_trm_is_used_on_the_date_it_is_published_for(self):
        trms = {
            date(2026, 9, 21): 3180.11,
            date(2026, 9, 22): 3196.00,
            date(2026, 9, 23): 3209.03,
        }
        for published_for, trm in trms.items():
            self.fetch(published_for, trm)

        for published_for, trm in trms.items():
            self.assertEqual(
                self.cop._convert(1000000, self.usd, self.company, published_for),
                self.usd.round(1000000 / trm),
                'a conversion on %s must use the TRM published for that date' % published_for,
            )
