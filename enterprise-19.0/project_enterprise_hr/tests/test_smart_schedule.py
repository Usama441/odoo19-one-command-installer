# Part of Odoo. See LICENSE file for full copyright and licensing details

from datetime import datetime
from dateutil.relativedelta import relativedelta
from odoo.tests import tagged, freeze_time
from odoo.addons.project_enterprise.tests.test_smart_schedule_common import TestSmartScheduleCommon
from .auto_shift_dates_hr_common import AutoShiftDatesHRCommon


@tagged('-at_install', 'post_install')
@freeze_time('2023-01-01')
class TestSmartSchedule(TestSmartScheduleCommon):
    def test_multi_users_tasks(self):
        """
            user_projectuser     [task_project_pigs_with_allocated_hours_user] [task_project_goats_with_allocated_hours_user]                                               [task_project_pigs_no_allocated_hours_user]
                                                                            |                                                                                                ^
                                                                            |                                                                                                |
                                                                            |                                                                                                |
            user_projectmanager                                             ------------------------------------------------>[task_project_pigs_with_allocated_hours_manager]-
            and user_projectuser
        """
        self.task_project_pigs_with_allocated_hours_manager.write({
            "user_ids": [self.user_projectmanager.id, self.user_projectuser.id],
            "depend_on_ids": [self.task_project_pigs_with_allocated_hours_user.id],
            "dependent_ids": [self.task_project_pigs_no_allocated_hours_user.id],
            "date_deadline": datetime(2023, 2, 2),
            "allocated_hours": 10.0,  # allocated hours should be equal remaining hours when timesheet_grid installed to have some hours to plan ( for testing simplicity )
        })

        self.task_project_pigs_no_allocated_hours_user.write({
            "user_ids": [self.user_projectuser.id],
        })

        self.env["hr.employee"].create([{
            "name": self.user_projectuser.name,
            "user_id": self.user_projectuser.id
        }, {
            "name": self.user_projectmanager.name,
            "user_id": self.user_projectmanager.id
        }])

        self.env['resource.calendar.leaves'].create([{
            'name': 'scheduled leave',
            'date_from': datetime(2023, 1, 3, 0),
            'date_to': datetime(2023, 1, 6, 23),
            'resource_id': self.user_projectuser.employee_id.resource_id.id,
            'time_type': 'leave',
        }, {
            'name': 'scheduled leave',
            'date_from': datetime(2023, 1, 5, 0),
            'date_to': datetime(2023, 1, 10, 23),
            'resource_id': self.user_projectmanager.employee_id.resource_id.id,
            'time_type': 'leave',
        }])

        result = (
            self.task_project_pigs_with_allocated_hours_user + self.task_project_pigs_with_allocated_hours_manager + self.task_project_pigs_no_allocated_hours_user + self.task_project_goats_with_allocated_hours_user
        ).with_context({
            'last_date_view': self.end_date_view_str,
            'gantt_scale': "week",
            'cell_part': 2.0,
        }).schedule_tasks({
            'planned_date_begin': self.start_date_view_str,
            'date_deadline': (self.start_date_view + relativedelta(day=1)).strftime('%Y-%m-%d %H:%M:%S'),
            'user_ids': self.user_projectuser.ids,
        })
        # Test no warning is displayed
        self.assertDictEqual(result[0], {}, 'No warnings should be displayed')

        self.assertEqual(self.task_project_pigs_with_allocated_hours_user.planned_date_begin, datetime(2023, 1, 2, 7))
        self.assertEqual(self.task_project_pigs_with_allocated_hours_user.date_deadline, datetime(2023, 1, 2, 16))

        # user_projectuser is off till 6
        # user_projectmanager is off till 10
        # the first possible time for both of them is starting from 11
        self.assertEqual(self.task_project_pigs_with_allocated_hours_manager.planned_date_begin, datetime(2023, 1, 11, 7))
        self.assertEqual(self.task_project_pigs_with_allocated_hours_manager.date_deadline, datetime(2023, 1, 11, 13), "10 hours to do / 2 users = 5 hours per user from 7h to 11h + 12h to 13h")

        # even that task_project_pigs_with_allocated_hours_manager was planned first as it has a deadline
        # smart scheduling is optimizing resources so
        # the gap in days 09 and 10 was filled to plan task_project_goats_with_allocated_hours_user
        self.assertEqual(self.task_project_goats_with_allocated_hours_user.planned_date_begin, datetime(2023, 1, 9, 7))
        self.assertEqual(self.task_project_goats_with_allocated_hours_user.date_deadline, datetime(2023, 1, 10, 9))

        # should not be planned after the old deadline of its parent, as its parent will be planned again
        # if the new deadline is before the old one, no need to block the task and plan it ASAP
        self.assertEqual(self.task_project_pigs_no_allocated_hours_user.planned_date_begin, datetime(2023, 1, 11, 13))
        self.assertEqual(self.task_project_pigs_no_allocated_hours_user.date_deadline, datetime(2023, 1, 13, 8), "12h to plan, 3 hours day 11, 8 hours day 12, 1 hour day 13")


class ProjectEnterpriseHrTestSmartScheduleWithVersion(AutoShiftDatesHRCommon):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.armande_employee.version_id.write({
            'date_version': datetime(2023, 1, 1),
            'contract_date_start': datetime(2023, 1, 1),
            'contract_date_end': datetime(2023, 8, 10),
            'name': 'CDD Contract for Armande ProjectUser',
            'resource_calendar_id': cls.calendar_morning.id,
            'wage': 5000.0,
        })
        cls.contract = cls.armande_employee.version_id

    def test_auto_plan_with_expired_contract(self):
        self.task_1.write({
            "planned_date_begin": False,
            "date_deadline": False,
        })

        res = self.task_1.with_context({
            'last_date_view': '2023-10-31 22:00:00',
            'cell_part': 2.0,
        }).schedule_tasks({
            'planned_date_begin': '2023-08-15 22:00:00',
            'date_deadline': '2023-10-16 21:59:59',
            'user_ids': self.armande_employee.user_id.ids,
        })

        self.assertEqual(next(iter(res[0].keys())), 'no_intervals')
        self.assertEqual(res[1], {}, "no pills planned")
        self.assertFalse(self.task_1.planned_date_begin)
        self.assertFalse(self.task_1.date_deadline)
