# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo.tests.common import TransactionCase
from odoo.fields import Date

from freezegun import freeze_time

PAY_SCHEDULES = {
    'quarterly': {
        'date_from': Date.to_date('2023-04-01'),
        'date_to': Date.to_date('2023-06-30'),
    },
    'semi-annually': {
        'date_from': Date.to_date('2023-01-01'),
        'date_to': Date.to_date('2023-06-30'),
    },
    'annually': {
        'date_from': Date.to_date('2023-01-01'),
        'date_to': Date.to_date('2023-12-31'),
    },
    'weekly': {
        'date_from': Date.to_date('2023-04-10'),
        'date_to': Date.to_date('2023-04-16'),
    },
    'bi-weekly': {
        'date_from': Date.to_date('2023-04-10'),
        'date_to': Date.to_date('2023-04-23'),
    },
    'bi-monthly': {
        'date_from': Date.to_date('2023-03-01'),
        'date_to': Date.to_date('2023-04-30'),
    },
    'daily': {
        'date_from': Date.to_date('2023-04-12'),
        'date_to': Date.to_date('2023-04-12'),
    }
}

class TestScheduleRelativePayslip(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.structure_type = cls.env['hr.payroll.structure.type'].create({
            'name': 'Test - Seaman',
        })
        cls.structure = cls.env['hr.payroll.structure'].create([{
            'name': 'Seaman Monthly Pay',
            'type_id': cls.structure_type.id,
            'schedule_pay': 'monthly',
        }])
        cls.structure_type.default_struct_id = cls.structure

        cls.billy_emp = cls.env['hr.employee'].create({
            'name': 'Billy Bones',
            'sex': 'male',
            'birthday': '1982-03-29',
            'date_version': Date.to_date('2023-01-01'),
            'contract_date_start': Date.to_date('2023-01-01'),
            'contract_date_end': Date.to_date('2023-12-31'),
            'wage': 5000.33,
            'structure_type_id': cls.structure_type.id,
        })
        cls.billy_contract = cls.billy_emp.version_id

    def test_payslip_computes(self):
        with freeze_time('2023-03-12'):
            payslip = self.env['hr.payslip'].new({
                'name': 'Black Spot',
                'employee_id': self.billy_emp.id,
            })
            self.assertEqual(payslip.version_id, self.billy_contract)
            self.assertEqual(payslip.struct_id, self.structure)
            self.assertEqual(payslip.date_from, Date.to_date('2023-03-01'))
            self.assertEqual(payslip.date_to, Date.to_date('2023-03-31'))
            payslip.write({
                'date_from': Date.to_date('2023-01-01'),
            })
            self.assertEqual(payslip.date_to, Date.to_date('2023-01-31'))

    def test_payslip_adapting_to_schedule(self):
        with freeze_time('2023-04-12'):
            payslip_monthly = self.env['hr.payslip'].new({
                'name': 'Black Spot',
                'employee_id': self.billy_emp.id,
            })
            self.assertEqual(payslip_monthly.date_from, Date.to_date('2023-04-01'), "date_from for the monthly payslip should be 2023-04-01")
            self.assertEqual(payslip_monthly.date_to, Date.to_date('2023-04-30'), "date_to for the monthly payslip should be 2023-04-30")

            for pay_schedule, dates in PAY_SCHEDULES.items():
                self.billy_contract.write({
                    'schedule_pay': pay_schedule,
                })
                payslip = self.env['hr.payslip'].new({
                    'name': 'Black Spot',
                    'employee_id': self.billy_emp.id,
                })
                self.assertEqual(payslip.date_from, dates['date_from'], "date_from for the %s payslip should be %s" % (pay_schedule, dates['date_from']))
                self.assertEqual(payslip.date_to, dates['date_to'], "date_to for the %s payslip should be %s" % (pay_schedule, dates['date_to']))

    def test_payslip_warnings(self):
        with freeze_time('2023-04-12'):
            self.billy_contract.write({
                'schedule_pay': 'quarterly',
            })
            payslip = self.env['hr.payslip'].new({
                'name': 'Black Spot February',
                'employee_id': self.billy_emp.id,
            })

            payslip.date_from = Date.to_date('2022-01-31')
            self.assertTrue(
                payslip.issues and "No running contract over payslip period" in [issue['message'] for issue in payslip.issues.values()],
                "An error should be set on contract validity.")

            payslip.date_to = Date.to_date('2022-05-14')
            self.assertTrue(
                payslip.issues and "No running contract over payslip period" in [issue['message'] for issue in payslip.issues.values()],
                "An error should be set on contract validity.")
            self.assertTrue(
                payslip.issues and "The duration of the payslip is not accurate according to the structure type." in [issue['message'] for issue in payslip.issues.values()],
                "A warning should be set on structure type duration.")
