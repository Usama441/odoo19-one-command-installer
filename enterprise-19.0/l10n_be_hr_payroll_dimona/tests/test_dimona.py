# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

from datetime import date
from unittest.mock import patch
from dateutil.relativedelta import relativedelta

import requests

from odoo.addons.l10n_be_hr_payroll_dimona.models.hr_version import HrVersion
from odoo.tests.common import TransactionCase
from odoo.tests import tagged


@tagged('post_install', '-at_install', 'post_install_l10n', 'dimona')
@patch.object(HrVersion, '_dimona_authenticate', lambda version: 'dummy-token')
@patch.object(HrVersion, '_cron_l10n_be_check_dimona', lambda version: True)
class TestDimona(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.belgium = cls.env.ref('base.be')

        cls.env.company.write({
            'country_id': cls.belgium.id,
            'onss_registration_number': '12548245',
        })

        cls.employee = cls.env['hr.employee'].create({
            'name': 'Test Employee',
            'niss': '93051822361',
            'private_street': '23 Test Street',
            'private_city': 'Test City',
            'private_zip': '6800',
            'private_country_id': cls.belgium.id,
            'wage': 2000,
            'date_version': date.today() + relativedelta(day=1, months=1),
            'contract_date_start': date.today() + relativedelta(day=1, months=1),
        })

        cls.version = cls.employee.version_id

    def test_dimona_open_classic(self):
        wizard = self.env['l10n.be.dimona.wizard'].create({
            'employee_id': self.employee.id,
            'version_id': self.version.id,
            'declaration_type': 'in',
        })

        def _patched_request(*args, **kwargs):
            response = requests.Response()
            response.headers = {'Location': 'foo/bar/blork/2029409422'}
            response.status_code = 201
            return response

        with patch('requests.sessions.Session.request', side_effect=_patched_request):
            wizard.submit_declaration()

        self.assertEqual(self.version.l10n_be_dimona_in_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_last_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_declaration_state, 'waiting')

    def test_dimona_open_foreigner(self):
        self.employee.write({
            'birthday': date(1991, 7, 28),
            'place_of_birth': 'Paris',
            'country_of_birth': self.env.ref('base.fr').id,
            'country_id': self.env.ref('base.fr').id,
            'sex': 'male',
        })

        wizard = self.env['l10n.be.dimona.wizard'].create({
            'employee_id': self.employee.id,
            'version_id': self.version.id,
            'declaration_type': 'in',
            'without_niss': True,
        })

        def _patched_request(*args, **kwargs):
            response = requests.Response()
            response.headers = {'Location': 'foo/bar/blork/2029409422'}
            response.status_code = 201
            return response

        with patch('requests.sessions.Session.request', side_effect=_patched_request):
            wizard.submit_declaration()

        self.assertEqual(self.version.l10n_be_dimona_in_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_last_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_declaration_state, 'waiting')

    def test_dimona_open_student(self):
        self.version.write({
            'structure_type_id': self.env.ref('l10n_be_hr_payroll.structure_type_student').id,
            'l10n_be_dimona_planned_hours': 130,
            'date_end': date.today() + relativedelta(months=1, day=31),
        })
        wizard = self.env['l10n.be.dimona.wizard'].create({
            'employee_id': self.employee.id,
            'version_id': self.version.id,
            'declaration_type': 'in',
        })

        def _patched_request(*args, **kwargs):
            response = requests.Response()
            response.headers = {'Location': 'foo/bar/blork/2029409422'}
            response.status_code = 201
            return response

        with patch('requests.sessions.Session.request', side_effect=_patched_request):
            wizard.submit_declaration()

        self.assertEqual(self.version.l10n_be_dimona_in_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_last_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_declaration_state, 'waiting')

    def test_dimona_close(self):
        self.version.write({
            'l10n_be_dimona_in_declaration_number': '2029409422',
            'contract_date_end': date.today() + relativedelta(months=1, day=31),
        })

        wizard = self.env['l10n.be.dimona.wizard'].create({
            'employee_id': self.employee.id,
            'version_id': self.version.id,
            'declaration_type': 'out',
        })

        def _patched_request(*args, **kwargs):
            response = requests.Response()
            response.headers = {'Location': 'foo/bar/blork/309320239'}
            response.status_code = 201
            return response

        with patch('requests.sessions.Session.request', side_effect=_patched_request):
            wizard.submit_declaration()

        self.assertEqual(self.version.l10n_be_dimona_in_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_last_declaration_number, '309320239')
        self.assertEqual(self.version.l10n_be_dimona_declaration_state, 'waiting')

    def test_dimona_update(self):
        self.version.write({
            'l10n_be_dimona_in_declaration_number': '2029409422',
            'date_end': date.today() + relativedelta(months=1, day=31),
        })

        wizard = self.env['l10n.be.dimona.wizard'].create({
            'employee_id': self.employee.id,
            'version_id': self.version.id,
            'declaration_type': 'update',
        })

        def _patched_request(*args, **kwargs):
            response = requests.Response()
            response.headers = {'Location': 'foo/bar/blork/309320239'}
            response.status_code = 201
            return response

        with patch('requests.sessions.Session.request', side_effect=_patched_request):
            wizard.submit_declaration()

        self.assertEqual(self.version.l10n_be_dimona_in_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_last_declaration_number, '309320239')
        self.assertEqual(self.version.l10n_be_dimona_declaration_state, 'waiting')

    def test_dimona_cancel(self):
        self.version.l10n_be_dimona_in_declaration_number = '2029409422'

        wizard = self.env['l10n.be.dimona.wizard'].create({
            'employee_id': self.employee.id,
            'version_id': self.version.id,
            'declaration_type': 'cancel',
        })

        def _patched_request(*args, **kwargs):
            response = requests.Response()
            response.headers = {'Location': 'foo/bar/blork/309320239'}
            response.status_code = 201
            return response

        with patch('requests.sessions.Session.request', side_effect=_patched_request):
            wizard.submit_declaration()

        self.assertEqual(self.version.l10n_be_dimona_in_declaration_number, '2029409422')
        self.assertEqual(self.version.l10n_be_dimona_last_declaration_number, '309320239')
        self.assertEqual(self.version.l10n_be_dimona_declaration_state, 'waiting')
