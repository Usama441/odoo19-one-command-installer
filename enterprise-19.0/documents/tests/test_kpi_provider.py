from odoo.tests import tagged
from odoo.tests.common import TransactionCase


@tagged('post_install', '-at_install')
class TestKpiProvider(TransactionCase):

    def test_kpi_summary(self):
        # Clean things for the test
        self.env['documents.document'].search([('type', '!=', 'folder')]).unlink()
        self.assertCountEqual(self.env['kpi.provider'].get_documents_kpi_summary(),
                              [{'id': 'documents.inbox', 'name': 'Inbox', 'type': 'integer', 'value': 0}])

        all_documents = self.env['documents.document'].create([{
            'folder_id': self.ref('documents.document_inbox_folder'),
        }] * 2)
        self.assertCountEqual(self.env['kpi.provider'].get_documents_kpi_summary(),
                              [{'id': 'documents.inbox', 'name': 'Inbox', 'type': 'integer', 'value': 2}])

        all_documents[0].folder_id = self.ref('documents.document_internal_folder')
        self.assertCountEqual(self.env['kpi.provider'].get_documents_kpi_summary(),
                              [{'id': 'documents.inbox', 'name': 'Inbox', 'type': 'integer', 'value': 1}])

        self.env.ref('documents.document_inbox_folder').unlink()
        self.assertCountEqual(self.env['kpi.provider'].get_documents_kpi_summary(), [])
