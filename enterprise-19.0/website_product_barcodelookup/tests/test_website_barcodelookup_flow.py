from odoo.tests import tagged
from ...product_barcodelookup.tests.test_barcodelookup_flow import TestBarcodelookup


@tagged('post_install', '-at_install')
class TestWebsiteBarcodelookup(TestBarcodelookup):

    def test_01_website_barcodelookup_flow(self):
        with self.mockBarcodelookupAutofill():
            self.start_tour('/', 'test_01_website_barcodelookup_flow', login="admin")
        product = self.env['product.template'].sudo().search([('name', '=', 'Odoo Scale up')], limit=1)
        self._verify_product_data(product, normalized_view=True)
        #  Product created from website should be published by default
        self.assertTrue(product.is_published)
