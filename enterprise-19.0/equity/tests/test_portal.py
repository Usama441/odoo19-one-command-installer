from datetime import date
from unittest.mock import patch

from freezegun import freeze_time

from odoo.fields import Command
from odoo.http import Request
from odoo.tests.common import HttpCase

from odoo.addons.equity.controllers.portal import PortalEquity
from odoo.addons.equity.tests.common import TestEquityCommon


class TestEquityPortal(TestEquityCommon, HttpCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.login = 'portal_user'
        cls.portal_user = cls.env['res.users'].create({
            'name': cls.login,
            'login': cls.login,
            'password': cls.login,
            'group_ids': [Command.set([cls.env.ref('base.group_portal').id])],
        })
        cls.access_token = cls.portal_user.partner_id._equity_ensure_token()

    def test_portal_my_equity(self):
        self.env['equity.transaction'].create([
            {
                'partner_id': self.company.id,
                'subscriber_id': self.portal_user.partner_id.id,
                'date': '2010-01-01',
                'transaction_type': 'issuance',
                'securities': 75,
                'security_price': 10,
                'security_class_id': self.share_class_ord.id,
            },
            {
                'partner_id': self.company.id,
                'subscriber_id': self.contact_2.id,
                'date': '2010-01-01',
                'transaction_type': 'issuance',
                'securities': 25,
                'security_price': 7,
                'security_class_id': self.share_class_ord.id,
            },
        ])

        self.authenticate(self.login, self.login)
        response = self.url_open('/my/equity/')
        self.assertEqual(response.status_code, 200)

        def assert_prepare_my_companies_values(self, access_token=None):
            nonlocal return_value
            return_value = super_prepare_my_companies_values(self, access_token)
            return return_value
        super_prepare_my_companies_values = PortalEquity._prepare_my_companies_values
        return_value = None

        with patch.object(PortalEquity, '_prepare_my_companies_values', assert_prepare_my_companies_values):
            response = self.url_open('/my/equity/', data={
                'access_token': self.access_token,
                'csrf_token': Request.csrf_token(self),
            })

        self.assertEqual(response.status_code, 200)
        self.assertEqual(return_value['partners'], [
            {'id': self.company.id, 'display_name': 'Company', 'securities': 75},
        ])

    def test_portal_my_company_equity(self):
        self.env['equity.transaction'].create([
            {
                'partner_id': self.company.id,
                'subscriber_id': self.portal_user.partner_id.id,
                'date': '2010-01-01',
                'transaction_type': 'issuance',
                'securities': 50,
                'security_price': 10,
                'security_class_id': self.share_class_ord.id,
            },
            {
                'partner_id': self.company.id,
                'subscriber_id': self.portal_user.partner_id.id,
                'date': '2010-06-02',
                'transaction_type': 'issuance',
                'securities': 50,
                'security_price': 10,
                'security_class_id': self.share_class_ord.id,
            },
            {
                'partner_id': self.company.id,
                'subscriber_id': self.portal_user.partner_id.id,
                'date': '2010-06-02',
                'transaction_type': 'issuance',
                'securities': 100,
                'security_price': 10,
                'security_class_id': self.option_class_1.id,
            },
            {
                'partner_id': self.company.id,
                'subscriber_id': self.portal_user.partner_id.id,
                'date': '2010-06-03',
                'transaction_type': 'exercise',
                'securities': 30,
                'security_price': 10,
                'security_class_id': self.option_class_1.id,
                'destination_class_id': self.share_class_b.id,
            },
            {
                'partner_id': self.company.id,
                'subscriber_id': self.portal_user.partner_id.id,
                'date': '2010-06-03',
                'transaction_type': 'cancellation',
                'securities': 30,
                'security_price': 10,
                'security_class_id': self.option_class_1.id,
            },
            {
                'partner_id': self.company.id,
                'subscriber_id': self.contact_2.id,
                'date': '2010-01-01',
                'transaction_type': 'issuance',
                'securities': 100,
                'security_price': 7,
                'security_class_id': self.share_class_ord.id,
            },
        ])
        self.env['equity.valuation'].create([{
            'event': 'transaction',
            'partner_id': self.company.id,
            'date': '2010-08-01',
            'valuation': 2000,
        }])

        self.authenticate(self.login, self.login)
        response = self.url_open(f'/my/equity/{self.company.id}')
        self.assertEqual(response.status_code, 200)

        def assert_prepare_my_transactions_values(self, partner_id, access_token=None):
            nonlocal return_value
            return_value = super_prepare_my_transactions_values(self, partner_id, access_token)
            return return_value
        super_prepare_my_transactions_values = PortalEquity._prepare_my_transactions_values
        return_value = None

        with (
            patch.object(PortalEquity, '_prepare_my_transactions_values', assert_prepare_my_transactions_values),
            freeze_time('2010-12-31')
        ):
            response = self.url_open(f'/my/equity/{self.company.id}', data={
                'access_token': self.access_token,
                'csrf_token': Request.csrf_token(self),
            })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(return_value['transactions'], [
            {
                'is_exercise': False,
                'is_options_issuance': False,
                'date': date(2010, 1, 1),
                'expiration_date': '',
                'event': 'Issuance',
                'security_class': 'ORD',
                'securities': 50.0,
                'security_price': 10.0,
                'transaction_price': -500.0,
            },
            {
                'is_exercise': False,
                'is_options_issuance': False,
                'date': date(2010, 6, 2),
                'expiration_date': '',
                'event': 'Issuance',
                'security_class': 'ORD',
                'securities': 50.0,
                'security_price': 10.0,
                'transaction_price': -500.0,
            },
            {
                'is_exercise': False,
                'is_options_issuance': True,
                'date': date(2010, 6, 2),
                'expiration_date': date(2013, 6, 2),
                'event': 'Issuance',
                'security_class': 'Option pool 1',
                'securities': 100.0,
                'security_price': 10.0,
                'transaction_price': 1000.0,
            },
            {
                'is_exercise': True,
                'is_options_issuance': False,
                'date': date(2010, 6, 3),
                'expiration_date': '',
                'event': 'Option Exercise',
                'security_class': 'Option pool 1 → Class B',
                'securities': 30.0,
                'security_price': 10.0,
                'transaction_price': -300.0,
            },
            {
                'is_exercise': False,
                'is_options_issuance': False,
                'date': date(2010, 6, 3),
                'expiration_date': '',
                'event': 'Cancellation',
                'security_class': 'Option pool 1',
                'securities': -30.0,
                'security_price': 10.0,
                'transaction_price': 300.0,
            },
            {
                'add_total_tooltip': True,
                'event': 'Total',
                'securities': 170.0,
                'transaction_price': -1000.0,
            },
        ])
        self.assertEqual(return_value['chart_props']['data'], {
            'Feb 2010': [1000 / 3, 1000.0],
            'Mar 2010': [1000 / 3, 1000.0],
            'Apr 2010': [1000 / 3, 1000.0],
            'May 2010': [1000 / 3, 1000.0],
            'Jun 2010': [1000 / 3, 1000.0],
            'Jul 2010': [(130 / 230) * 1000.0, 1000.0],
            'Aug 2010': [(130 / 230) * 2000.0, 2000.0],
            'Sep 2010': [(130 / 230) * 2000.0, 2000.0],
            'Oct 2010': [(130 / 230) * 2000.0, 2000.0],
            'Nov 2010': [(130 / 230) * 2000.0, 2000.0],
            'Dec 2010': [(130 / 230) * 2000.0, 2000.0],
            'Jan 2011': [(130 / 230) * 2000.0, 2000.0],
        })
        self.assertEqual(return_value['chart_props']['stats'], {
            'valuation': 2000,
            'yourValuation': (130 / 230) * 2000.0,
            'ownership': 130 / 230,
            'votingRights': 130 / 230,
            'currencyId': self.env.company.currency_id.id,
        })
