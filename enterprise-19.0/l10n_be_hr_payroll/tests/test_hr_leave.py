# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo.tests import tagged
from .common import TestPayrollCommon


@tagged('post_install_l10n', 'post_install', '-at_install', 'payroll_right_to_legal_leaves')
class TestPayrollRightToLegalLeaves(TestPayrollCommon):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

    def test_edrs_activity_not_logged_without_notified_officers(self):
        """
        Create a time off request using a leave_type which doesn't have 'Notified Time Off Officers' and assert
        that eDRS activity isn't logged to the chatter.
        """
        leave_type_without_notified_officers = self.env['hr.leave.type'].create({
            'name': 'Leave Type Without Notified Officers',
            'requires_allocation': False,
            'employee_requests': True,
            'leave_validation_type': 'both',
            'responsible_ids': False,
            'request_unit': 'day'
        })
        leave_request = self.env['hr.leave'].create({
            'name': 'Leave 1 day',
            'employee_id': self.employee_georges.id,
            'holiday_status_id': leave_type_without_notified_officers.id,
            'request_date_from': '2024-10-31',
            'request_date_to': '2024-10-31',
        })
        leave_request.action_approve()
        activity = self.env['mail.activity'].search([
            ('res_id', '=', leave_request.id),
            ('res_model', '=', 'hr.leave'),
        ])
        self.assertFalse(activity)
