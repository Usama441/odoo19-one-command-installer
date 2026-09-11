# Part of Odoo. See LICENSE file for full copyright and licensing details.

from datetime import date, datetime

from odoo.tests import tagged

from .common import HrWorkEntryAttendanceCommon


@tagged('-at_install', 'post_install', 'work_entry_attendance')
class TestWorkentryAttendance(HrWorkEntryAttendanceCommon):

    def test_basic_generation(self):
        # Create an attendance for each afternoon of september
        attendance_vals_list = []
        for i in range(1, 31):
            new_date = datetime(2021, 9, i, 13, 0, 0)
            if new_date.weekday() >= 5:
                continue
            attendance_vals_list.append({
                'employee_id': self.employee.id,
                'check_in': new_date,
                'check_out': new_date.replace(hour=17),
            })
        attendances = self.env['hr.attendance'].create(attendance_vals_list)
        work_entries = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id)])
        # Should not have generated a work entry since no period has been generated yet
        self.assertFalse(work_entries)
        self.contract.generate_work_entries(date(2021, 9, 1), date(2021, 9, 30))
        work_entries = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id)])
        self.assertEqual(len(attendances), len(work_entries))
        self.assertTrue(all(hwe.attendance_id for hwe in work_entries))

    def test_lunch_time_case(self):
        # only consider lunch time for non-flexible attendance based contracts
        week_day = datetime(2022, 9, 19, 8, 0, 0)
        weekend = datetime(2022, 9, 18, 8, 0, 0)
        self.env['hr.attendance'].create([
            {
                'employee_id': self.employee.id,
                'check_in': week_day,
                'check_out': week_day.replace(hour=20),
            },
            {
                'employee_id': self.employee.id,
                'check_in': weekend,
                'check_out': weekend.replace(hour=20),

            }
            ]
        )
        # We should have here 3 work entries in total
        # Sunday -> 08:00 -> 20:00
        # Monday -> 08:00 -> 12:00 and 13:00 -> 20:00
        self.contract.generate_work_entries(date(2022, 9, 18), date(2022, 9, 19))
        sunday = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id),
                                                   ('date', '<', week_day)])

        monday = self.env["hr.work.entry"].search([('employee_id', '=', self.employee.id),
                                                   ('date', '>=', week_day)])

        self.assertEqual(len(sunday), 1)
        self.assertEqual(sunday.date, date(2022, 9, 18))
        self.assertEqual(sunday.duration, 12)

        self.assertEqual(len(monday), 2)
        self.assertEqual(monday[0].date, date(2022, 9, 19))
        self.assertEqual(monday[0].duration, 8)
        self.assertEqual(monday[1].date, date(2022, 9, 19))
        self.assertEqual(monday[1].duration, 3)

        # set flexible hours on the employee contract
        self.contract.resource_calendar_id.flexible_hours = True
        flex_day = datetime(2022, 9, 20, 8, 0, 0)
        self.env['hr.attendance'].create([
            {
                'employee_id': self.employee.id,
                'check_in': flex_day,
                'check_out': flex_day.replace(hour=20),
            },
            ]
        )
        # We should have here 1 work entry
        # Tuesday -> 08:00 -> 20:00
        self.contract.generate_work_entries(date(2022, 9, 20), date(2022, 9, 21))
        tuesday = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id),
                                                   ('date', '>=', flex_day)])
        self.assertEqual(len(tuesday), 2)
        self.assertEqual(tuesday[0].date, date(2022, 9, 20))
        self.assertEqual(tuesday[0].duration, 8)
        self.assertEqual(tuesday[1].date, date(2022, 9, 20))
        self.assertEqual(tuesday[1].duration, 4)

    def test_timezones(self):
        """ Basic check that timezones do not cause weird behaviors:
            * check that the date range of ``generate_work_entries`` accounts for timezones.
            * check that times are all stored in utc and are not improperly converted
        """
        self.employee.version_id.resource_calendar_id.tz = 'Asia/Tokyo'

        monday_morning_tokyo = datetime(2024, 10, 20, 22, 0, 0)  # 22:00 sunday utc = 7:00 monday tokyo
        self.env['hr.attendance'].create({
            'employee_id': self.employee.id,
            'check_in': monday_morning_tokyo,
            'check_out': monday_morning_tokyo.replace(day=21, hour=6),  # 16:00
        })
        self.contract.generate_work_entries(date(2024, 10, 21), date(2024, 10, 21))

        we = self.env["hr.work.entry"].search([
            ('employee_id', '=', self.employee.id),
            ('date', '>=', monday_morning_tokyo)
        ])

        self.assertEqual(len(we), 1)
        self.assertEqual(we.date, date(2024, 10, 21))
        self.assertEqual(we.duration, 8)

    def test_attendance_within_period(self):
        # Tests that an attendance created within an already generated period generates a work entry
        boundaries_attendances = self.env['hr.attendance'].create([
            {
                'employee_id': self.employee.id,
                'check_in': datetime(2021, 9, 1, 14, 0, 0),
                'check_out': datetime(2021, 9, 1, 17, 0, 0),
            },
            {
                'employee_id': self.employee.id,
                'check_in': datetime(2021, 9, 30, 14, 0, 0),
                'check_out': datetime(2021, 9, 30, 17, 0, 0),
            },
        ])
        self.contract.generate_work_entries(date(2021, 9, 1), date(2021, 9, 30))
        work_entries = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id)])
        self.assertEqual(len(work_entries), len(boundaries_attendances))

        inner_attendance = self.env['hr.attendance'].create([
            {
                'employee_id': self.employee.id,
                'check_in': datetime(2021, 9, 14, 14, 0, 0),
                'check_out': datetime(2021, 9, 14, 17, 0, 0),
            }
        ])
        work_entries = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id)])
        self.assertEqual(len(work_entries), len(boundaries_attendances) + len(inner_attendance))

    def test_attendance_spanning_days(self):
        # Tests that attendances that cross midnight generate work entries that do not cross midnight
        # or conflict. 2 entries for init, 2 for the first attendance, and 4 for the second due to lunch
        self.contract.write({
            'date_generated_from': datetime(2021, 9, 1, 0, 0, 0),
            'date_generated_to': datetime(2021, 9, 30, 23, 59, 59),
        })
        self.env['hr.attendance'].create(
            {
            'employee_id': self.employee.id,
            'check_in': datetime(2021, 9, 10, 22, 0, 0),
            'check_out': datetime(2021, 9, 11, 6, 0, 0),
            }
        )
        self.env['hr.attendance'].create([
            {
                'employee_id': self.employee.id,
                'check_in': datetime(2021, 9, 11, 22, 0, 0),
                'check_out': datetime(2021, 9, 12, 6, 0, 0),
            },
            {
                'employee_id': self.employee.id,
                'check_in': datetime(2021, 9, 13, 22, 0, 0),
                'check_out': datetime(2021, 9, 15, 6, 0, 0),
            },
        ])
        work_entries = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id)])
        self.assertEqual(len(work_entries), 5)

    def test_unlink(self):
        # Tests that the work entry is archived when unlinking an attendance
        # Makes the attendance create a work entry directly
        self.contract.write({
            'date_generated_from': datetime(2021, 9, 1, 0, 0, 0),
            'date_generated_to': datetime(2021, 9, 30, 23, 59, 59),
        })
        attendance = self.env['hr.attendance'].create({
            'employee_id': self.employee.id,
            'check_in': datetime(2021, 9, 14, 14, 0, 0),
            'check_out': datetime(2021, 9, 14, 17, 0, 0),
        })
        work_entries = self.env['hr.work.entry'].search([('employee_id', '=', self.employee.id)])
        attendance.unlink()
        self.assertFalse(work_entries.active)

    def test_work_entries_exclude_refused_overtime(self):
        self.env['hr.attendance'].create({
            'employee_id': self.employee.id,
            'check_in': datetime(2021, 1, 4, 9, 0),
            'check_out': datetime(2021, 1, 4, 12, 0),
        })
        attendance = self.env['hr.attendance'].create({
            'employee_id': self.employee.id,
            'check_in': datetime(2021, 1, 4, 13, 0),
            'check_out': datetime(2021, 1, 4, 20, 0),
        })
        attendance.action_refuse_overtime()
        work_entries = self.contract.generate_work_entries(date(2021, 1, 4), date(2021, 1, 4))
        total_work_entry_duration = sum(work_entry.duration for work_entry in work_entries)
        self.assertEqual(total_work_entry_duration, self.employee.resource_calendar_id.hours_per_day)

    def test_fully_flexible_working_schedule_work_entries(self):
        """ Test employee with fully flexible working schedule with attendance as work entry source """
        employee = self.env['hr.employee'].create({
            'name': 'Test',
            'date_version': datetime(2024, 9, 1),
            'contract_date_start': datetime(2024, 9, 1),
            'contract_date_end': datetime(2024, 9, 30),
            'wage': 5000.0,
            'work_entry_source': 'attendance',
            'resource_calendar_id': False
        })

        self.env['resource.calendar.leaves'].sudo().create({
            'resource_id': employee.resource_id.id,
            'date_from': datetime(2024, 9, 2),
            'date_to': datetime(2024, 9, 3)
        })

        employee.generate_work_entries(datetime(2024, 9, 1), datetime(2024, 9, 30))
        result_entries = self.env['hr.work.entry'].search([('employee_id', '=', employee.id)])
        self.assertEqual(len(result_entries), 2, 'Two work entries should be generated')

        self.env['hr.attendance'].create({
            'employee_id': employee.id,
            'check_in': datetime(2024, 9, 14, 14, 0, 0),
            'check_out': datetime(2024, 9, 14, 17, 0, 0),
        })
        employee.generate_work_entries(datetime(2024, 9, 1), datetime(2024, 9, 30))
        result_entries = self.env['hr.work.entry'].search([('employee_id', '=', employee.id)])
        self.assertEqual(len(result_entries), 3, 'Two work entry should be generated')

    def test_gto_flexible_calendar(self):
        """
        Test when having a public time off and a flexible user has two
        separate attendances in this day what will be the duration of the
        holiday work entries.
        """
        start = datetime(2018, 1, 1, 6, 0, 0)
        end = datetime(2018, 1, 1, 18, 0, 0)
        self.env['resource.calendar.leaves'].create({
            'date_from': start,
            'date_to': end,
            'work_entry_type_id': self.work_entry_type_leave.id,
        })

        flexible_calendar = self.env['resource.calendar'].create({
            'name': 'flexible calendar',
            'flexible_hours': True,
            'full_time_required_hours': 40,
            'hours_per_day': 8,
        })

        self.richard_emp.version_id.write({
            'resource_calendar_id': flexible_calendar.id,
            'work_entry_source': 'attendance',
        })

        self.env['hr.attendance'].create([
            {
                'check_in': datetime(2018, 1, 1, 9, 0, 0),
                'check_out': datetime(2018, 1, 1, 11, 0, 0),
                'employee_id': self.richard_emp.id,
            },
            {
                'check_in': datetime(2018, 1, 1, 13, 0, 0),
                'check_out': datetime(2018, 1, 1, 15, 0, 0),
                'employee_id': self.richard_emp.id,
            }
        ])

        work_entries = self.richard_emp.version_ids.generate_work_entries(start.date(), end.date())
        time_off_entries = work_entries.filtered(lambda entry: entry.code == 'LEAVETEST100')
        # Since we are now merging similar work entries on the same day
        # we are going to have only one leave entry
        self.assertEqual(len(time_off_entries), 1)
        self.assertEqual(time_off_entries.duration, 8)
        self.assertEqual((work_entries - time_off_entries).duration, 4)
