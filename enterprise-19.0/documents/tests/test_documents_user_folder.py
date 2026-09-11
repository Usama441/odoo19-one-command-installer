from odoo import Command
from odoo.exceptions import UserError
from odoo.tests import users

from odoo.addons.documents.controllers.documents import ShareRoute
from odoo.addons.documents.tests.test_documents_common import TransactionCaseDocuments


class TestDocumentsUserFolder(TransactionCaseDocuments):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.document_sys_admin = cls.env['res.users'].create([
            {
                'group_ids': [Command.link(cls.env.ref('documents.group_documents_system').id)],
                'login': "doc_system",
                'name': "Documents System Administrator",
            },
        ])
        cls.company_doc, cls.company_restr, cls.internal_drive = cls.env["documents.document"].sudo().create([
            {'name': 'Company Document', 'owner_id': False, 'access_internal': 'view'},
            {'name': 'Company Document Restricted', 'owner_id': False},
            {'name': "Internal User's Drive Document", 'owner_id': cls.internal_user.id, 'type': 'folder'},
        ])
        cls.company_folder = cls.env['documents.document'].sudo().create({
            'name': 'Company Folder',
            'type': 'folder',
            'access_internal': 'edit',
            'owner_id': False,
        })
        cls.test_documents = (
            cls.company_doc  # no owner, access_internal='view'
            | cls.company_restr  # no owner, but no access to internal users
            | cls.internal_drive  # internal_user's drive
            | cls.folder_a  # doc_user's drive
            | cls.folder_a_a
            | cls.folder_b  # doc_user's drive
            | cls.company_folder
        )
        cls.folder_a.action_update_access_rights(
            access_internal='edit',
            partners={cls.portal_user.partner_id: ('view', False)}
        )
        # Log access to folder_a
        for user in cls.doc_user, cls.document_sys_admin, cls.portal_user, cls.internal_user:
            ShareRoute._upsert_last_access_date(cls.env(user=user), cls.folder_a)

        cls.company_restr.action_update_access_rights(partners={cls.doc_user.partner_id: ('view', False)})
        cls.env['documents.document'].search([('id', 'not in', cls.test_documents.ids)]).action_archive()

    def test_compute_user_folder_id(self):
        folder_a_id_str = str(self.folder_a.id)
        tests_users = self.internal_user, self.doc_user, self.portal_user, self.document_sys_admin
        expected_user_folder_ids = [
            # company_doc, company_restr, internal_drive, folder_a,      folder_a_a, folder_b, company_folder,
            [   'COMPANY',         False,           'MY', 'SHARED', folder_a_id_str, 'SHARED', 'COMPANY'],  # internal_user
            [   'COMPANY',     'COMPANY',          False,     'MY', folder_a_id_str,     'MY', 'COMPANY'],  # doc_user
            [       False,         False,          False,    False, folder_a_id_str,    False,     False],  # portal_user
            [   'COMPANY',     'COMPANY',       'SHARED', 'SHARED', folder_a_id_str, 'SHARED', 'COMPANY'],  # document_sys_admin
        ]
        for user, expected in zip(tests_users, expected_user_folder_ids):
            actual = self.test_documents.with_user(user).mapped('user_folder_id')
            with self.subTest(user=user.name):
                self.assertListEqual(actual, expected)

    @users('dtdm')
    def test_create_with_default_user_folder_id(self):
        context = {'default_user_folder_id': 'COMPANY'}
        no_folder = self.env['documents.document']
        no_user = self.env['res.users']
        cases = [
            (
                {'name': 'Company root, no vals'},
                {'folder_id': no_folder, 'owner_id': no_user}
            ), (
                {'name': 'In folder A > A from folder_id in vals', 'folder_id': self.folder_a_a.id},
                {'folder_id': self.folder_a_a, 'owner_id': self.document_manager, 'user_folder_id': str(self.folder_a_a.id)}
            ), (
                {'name': 'In folder A from user_folder_id in vals', 'user_folder_id': str(self.folder_a.id)},
                {'folder_id': self.folder_a, 'owner_id': self.document_manager, 'user_folder_id': str(self.folder_a.id)}
            ), (
                {'name': 'In My Drive from user_folder_id in vals', 'user_folder_id': 'MY'},
                {'folder_id': no_folder, 'owner_id': self.document_manager, 'user_folder_id': 'MY'}
            ), (
                {'name': 'In My Drive from owner_id in vals', 'owner_id': self.document_manager.id},
                {'folder_id': no_folder, 'owner_id': self.document_manager, 'user_folder_id': 'MY'}
            )
        ]
        for vals, expected in cases:
            with self.subTest(vals=vals):
                doc = self.env['documents.document'].with_context(context).create(vals)
                for key, value in expected.items():
                    self.assertEqual(doc[key], value)

    @users('internal_user')
    def test_create_write_user_folder_id(self):
        defaults, company, my, folder_a_b, folder_a_b_2 = self.env['documents.document'].with_context(
            default_folder_id=self.folder_a_a.id,
            default_owner_id=self.doc_user.id,
        ).create([
            {
                'name': 'defaults',
            },
            {
                'name': 'Company document',
                'user_folder_id': 'COMPANY',
            }, {
                'name': 'My Drive Document',
                'user_folder_id': 'MY',
            }, {
                'name': 'Folder A/B',
                'type': 'folder',
                'user_folder_id': str(self.folder_a.id),
            }, {
                'name': 'Document A/B2',
                'folder_id': self.folder_a.id,
                'user_folder_id': str(self.folder_a.id),
            }
        ])
        self.assertEqual(defaults.folder_id.id, self.folder_a_a.id)
        self.assertEqual(defaults.owner_id.id, self.doc_user.id)
        self.assertFalse(company.folder_id)
        self.assertFalse(company.owner_id)
        self.assertFalse(my.folder_id)
        self.assertEqual(my.owner_id, self.internal_user)  # user_folder_id=MY primes over context defaults
        self.assertEqual(folder_a_b.folder_id, self.folder_a)
        self.assertEqual(folder_a_b.owner_id, self.doc_user)  # context default used
        self.assertEqual(folder_a_b_2.folder_id, self.folder_a)

        for user_folder_id in ('ALL', 'RECENT', 'SHARED', 'TRASH'):
            with self.subTest(user_folder_id=user_folder_id):
                with self.assertRaises(UserError):
                    self.env['documents.document'].create({
                        'name': 'Should fail',
                        'user_folder_id': user_folder_id,
                    })
        for idx, values in enumerate((
            {'user_folder_id': str(self.folder_a_a.id), 'folder_id': self.folder_a.id},  # different folder_id
            {'user_folder_id': 'COMPANY', 'folder_id': self.folder_a.id},  # Company has folder_id=False
            {'user_folder_id': 'COMPANY', 'owner_id': self.internal_user.id},  # Company has owner_id=False
        )):
            with self.subTest(idx=idx):
                with self.subTest(kind='create'), self.assertRaises(UserError):
                    self.env['documents.document'].create(values)
                with self.subTest(kind='write'), self.assertRaises(UserError):
                    my.write(values)

    @users('internal_user')
    def test_search_child_of(self):
        my_subfolder, company_subfolder = self.env['documents.document'].create([
            {'name': 'My Subfolder', 'folder_id': self.internal_drive.id},
            {'name': 'Company Subfolder', 'type': 'folder', 'folder_id': self.company_folder.id},
        ])
        cases = [
            ('SHARED', self.folder_a | self.folder_a_a | self.folder_b),
            ('MY', self.internal_drive | my_subfolder),
            ('COMPANY', self.company_folder | company_subfolder | self.company_doc)
        ]
        for user_folder_id, expected in cases:
            with self.subTest(user_folder_id=user_folder_id):
                actual = self.env['documents.document'].search([('user_folder_id', 'child_of', user_folder_id)])
                self.assertEqual(actual, expected, f"Found {actual.mapped('name')}")

    def test_search_user_folder_id_equal(self):
        Document = self.env['documents.document']
        cases = [
            (self.internal_user, {
                'COMPANY': self.company_doc | self.company_folder,
                'MY': self.internal_drive,
                'SHARED': self.folder_a | self.folder_b,
                'RECENT': self.internal_drive | self.folder_a,
                str(self.folder_a.id): self.folder_a_a,
            }),
            (self.doc_user, {
                'COMPANY': self.company_doc | self.company_folder | self.company_restr,
                'MY': self.folder_a | self.folder_b,
                'SHARED': Document,
                'RECENT': self.folder_a | self.folder_a_a | self.folder_b,
                str(self.folder_a.id): self.folder_a_a,
            }),
            (self.portal_user, {
                'COMPANY': Document,
                'MY': Document,
                'SHARED': self.folder_a,
                'RECENT': self.folder_a,
                str(self.folder_a.id): self.folder_a_a,
            })
        ]
        for user, expected in cases:
            for user_folder_id, documents in expected.items():
                with self.subTest(user=user.name, user_folder_id=user_folder_id):
                    actual = self.env['documents.document'].with_user(user).search([('user_folder_id', '=', user_folder_id)])
                    self.assertEqual(actual, documents, f"Found: {actual.mapped('name')}")

    @users('internal_user')
    def test_search_user_folder_id_in_and_not_in(self):
        to_find_all = ['COMPANY', 'MY', 'SHARED', str(self.folder_a.id)]
        expected_all = self.company_doc | self.company_folder | self.internal_drive | self.folder_a | self.folder_a_a \
            | self.folder_b
        actual = self.env['documents.document'].search([('user_folder_id', 'in', to_find_all)])
        self.assertEqual(actual, expected_all, f"Found {actual.mapped('name')}")

        expected_company = self.company_doc | self.company_folder
        actual_company = self.env['documents.document'].search([('user_folder_id', 'in', 'COMPANY')])
        self.assertEqual(actual_company, expected_company, f"Found {actual_company.mapped('name')}")

        expected_not_company = expected_all - expected_company
        actual_not_company = self.env['documents.document'].search([('user_folder_id', 'not in', 'COMPANY')])
        self.assertEqual(actual_not_company, expected_not_company, f"Found {actual_not_company.mapped('name')}")

        expected_my = self.internal_drive
        actual_my = self.env['documents.document'].search([('user_folder_id', 'in', 'MY')])
        self.assertEqual(actual_my, expected_my, f"Found {actual_my.mapped('name')}")

        expected_not_my = expected_all - expected_my
        actual_not_my = self.env['documents.document'].search([('user_folder_id', 'not in', 'MY')])
        self.assertEqual(actual_not_my, expected_not_my, f"Found {actual_not_my.mapped('name')}")

        expected_shared = self.folder_a | self.folder_b
        actual_shared = self.env['documents.document'].search([('user_folder_id', 'in', 'SHARED')])
        self.assertEqual(actual_shared, expected_shared, f"Found {actual_shared.mapped('name')}")

        expected_not_shared = expected_all - expected_shared
        actual_not_shared = self.env['documents.document'].search([('user_folder_id', 'not in', 'SHARED')])
        self.assertEqual(actual_not_shared, expected_not_shared, f"Found {actual_not_shared.mapped('name')}")

        expected_folder_a = self.folder_a_a
        actual_folder_a = self.env['documents.document'].search([('user_folder_id', 'in', str(self.folder_a.id))])
        self.assertEqual(actual_folder_a, expected_folder_a, f"Found {actual_folder_a.mapped('name')}")

        expected_not_folder_a = expected_all - expected_folder_a
        actual_not_folder_a = self.env['documents.document'].search([('user_folder_id', 'not in', str(self.folder_a.id))])
        self.assertEqual(actual_not_folder_a, expected_not_folder_a, f"Found {actual_not_folder_a.mapped('name')}")
