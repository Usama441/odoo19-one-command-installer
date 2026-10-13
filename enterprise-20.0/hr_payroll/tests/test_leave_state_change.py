# Part of Odoo. See LICENSE file for full copyright and licensing details.
from freezegun import freeze_time

from odoo.exceptions import UserError
from odoo.tests.common import tagged
from odoo.addons.hr_payroll.tests.common import TestPayrollHolidaysBase


@tagged('post_install', '-at_install')
class TestLeaveStateChange(TestPayrollHolidaysBase):

    @freeze_time('2018-02-24 10:00:00')
    def test_leave_back_to_approval_leave_when_not_in_confirm_payslip(self):
        """
        ================================================================================================================
        | case 1: An approved leave can be moved back to confirm state if leave is not in done/paid payslip.           |
        | case 2: An approved leave can't be moved back to confirm state if leave is in done/paid payslip.             |
        ================================================================================================================
        """
        unpaid_work_entry_type = self.env['hr.work.entry.type'].create({
            'name': 'unpaid leave in days',
            'code': 'unpaid leave in days',
            'amount_rate': 0.0,
            'request_unit': 'day',
            'unit_of_measure': 'day',
            'leave_validation_type': 'both',
            'count_as': 'absence',
            'requires_allocation': False,
        })
        unpaid_leave = self.env['hr.leave'].with_user(self.emp.user_id).create({
            'name': 'unpaid leave for 3 days',
            'employee_id': self.emp.id,
            'work_entry_type_id': unpaid_work_entry_type.id,
            'request_date_from': '2018-02-23',
            'request_date_to': '2018-02-25',
        })

        unpaid_leave.with_user(self.joseph.id).action_approve()
        unpaid_leave.with_user(self.joseph.id).action_back_to_approval()
        self.assertEqual(
            unpaid_leave.state,
            "confirm",
            "Approved leave can be moved back to confirm state as long as not included in the done/paid payslip",
        )

        unpaid_leave.with_user(self.joseph).action_approve()
        payslip = self.env['hr.payslip'].create({
            'employee_id': self.emp.id,
        })
        payslip.compute_sheet()
        payslip.action_payslip_done()
        unpaid_leave.with_user(self.joseph).action_back_to_approval()
        self.assertEqual(
            unpaid_leave.state,
            "validate",
            "Approved leave can't be moved back to confirm state if included in done/paid payslip",
        )

    def test_category_options_validation_on_work_entry_type_change(self):
        category = self.env['hr.salary.rule.category'].create({
            'name': 'Test Category',
            'code': 'TEST_CAT',
        })
        wet_allowed = self.env['hr.work.entry.type'].create({
            'name': 'Work Entry Type Allowed',
            'code': 'WET_ALLOW',
            'requires_allocation': False,
            'optional_category_ids': [(6, 0, category.ids)],
            'leave_validation_type': 'hr'
        })
        wet_disallowed = self.env['hr.work.entry.type'].create({
            'name': 'Work Entry Type Disallowed',
            'code': 'WET_DISALLOW',
            'requires_allocation': False,
            'leave_validation_type': 'hr'
        })

        leave = self.env['hr.leave'].with_user(self.emp.user_id).create({
            'name': 'Test Leave',
            'employee_id': self.emp.id,
            'work_entry_type_id': wet_allowed.id,
            'request_date_from': '2018-02-23',
            'request_date_to': '2018-02-23',
        }).sudo()

        leave.write({'category_options_ids': [(6, 0, category.ids)]})

        with self.assertRaises(UserError, msg="You cannot select the option(s) 'Test Category' for the time off type 'Work Entry Type Disallowed'."):
            leave.write({'work_entry_type_id': wet_disallowed.id})

        leave.write({
            'work_entry_type_id': wet_disallowed.id,
            'category_options_ids': [(5, 0, 0)]
        })
        self.assertEqual(leave.work_entry_type_id, wet_disallowed)
        self.assertFalse(leave.category_options_ids)
