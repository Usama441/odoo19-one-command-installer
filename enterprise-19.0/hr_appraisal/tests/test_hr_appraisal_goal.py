# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo.tests import Form
from odoo.tests.common import TransactionCase


class TestHrAppraisal(TransactionCase):
    """ Test used to check that when doing appraisal creation."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.user_without_hr_right = cls.env['res.users'].create({
            'name': 'Test without hr right',
            'login': 'test_without_hr_right',
            'group_ids': [(6, 0, [cls.env.ref('base.group_user').id])],
            'notification_type': 'email',
        })
        cls.user_without_hr_right.action_create_employee()
        cls.employee_without_hr_right = cls.user_without_hr_right.employee_ids[0]
        cls.employee_subordinate = cls.env['hr.employee'].create({
            'name': 'Gerard',
            'parent_id': cls.employee_without_hr_right.id,
        })

    def test_create_goal_without_hr_right(self):
        goal_form = Form(self.env['hr.appraisal.goal'].with_user(self.user_without_hr_right).with_context(
            {'uid': self.user_without_hr_right.id}
        ))
        goal_form.name = "My goal"
        goal_form.employee_ids = self.employee_subordinate
        goal_form.save()
