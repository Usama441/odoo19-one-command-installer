# Part of Odoo. See LICENSE file for full copyright and licensing details.

from datetime import date, timedelta

from odoo.tests import tagged

from .common import TestPayrollCommon


@tagged('work_hours_split_half')
@tagged('post_install_l10n', 'post_install', '-at_install')
class TestWorkHoursSplitHalf(TestPayrollCommon):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.work_entry_type = cls.env.ref('hr_work_entry.be_work_entry_type_attendance')

        cls.fixed_uneven = cls.env['resource.calendar'].create({
            'name': 'Fixed 8h Mon-Thu / 4h Fri',
            'company_id': cls.belgian_company.id,
            'calendar_type': 'fixed',
            'days_per_week': 5.0,
            'hours_per_week': 36.0,
            'full_time_required_hours': 38,
            'attendance_ids': [
                (0, 0, {'dayofweek': str(day), 'hour_from': 8, 'hour_to': 16})
                for day in range(4)
            ] + [
                (0, 0, {'dayofweek': '4', 'hour_from': 8, 'hour_to': 12}),
            ],
        })

        cls.variable_uneven = cls.env['resource.calendar'].create({
            'name': 'Variable 8h Mon-Thu / 4h Fri',
            'company_id': cls.belgian_company.id,
            'calendar_type': 'variable',
            'days_per_week': 5.0,
            'hours_per_week': 36.0,
            'full_time_required_hours': 38,
            'attendance_ids': [
                (0, 0, {
                    'date': date(1, 1, 1) + timedelta(days=i),
                    'hour_from': 8, 'hour_to': 16,
                    'recurrency': True, 'recurrency_interval': 1, 'recurrency_type': 'weeks',
                }) for i in range(4)
            ] + [
                (0, 0, {
                    'date': date(1, 1, 1) + timedelta(days=4),
                    'hour_from': 8, 'hour_to': 12,
                    'recurrency': True, 'recurrency_interval': 1, 'recurrency_type': 'weeks',
                }),
            ],
        })

        cls.employee_fixed = cls.create_employee({
            'name': 'Fixed Uneven Employee',
            'date_version': date(2024, 1, 1),
            'contract_date_start': date(2024, 1, 1),
            'resource_calendar_id': cls.fixed_uneven.id,
        })
        cls.employee_variable = cls.create_employee({
            'name': 'Variable Uneven Employee',
            'date_version': date(2024, 1, 1),
            'contract_date_start': date(2024, 1, 1),
            'resource_calendar_id': cls.variable_uneven.id,
        })

        cls.monday = date(2024, 1, 1)
        cls.friday = date(2024, 1, 5)
        cls.friday_later = date(2024, 1, 26)

    def _split(self, employee, day, duration):
        version = employee.version_id
        work_entries_vals = [{
            'version_id': version,
            'date': day,
            'work_entry_type_id': self.work_entry_type,
            'duration': duration,
        }]
        work_data = version._get_work_hours_split_half(day, day, work_entries_vals)
        # _get_work_hours_split_half keys on (half/full, work_entry_type_id, category_options)
        # and is a defaultdict: drop the (here always empty) options and return a plain dict so a
        # missing key raises instead of silently yielding [0, 0].
        return {
            work_entry_type_id: values
            for (work_entry_type_id, _options), values in work_data.items()
        }

    def test_fixed_calendar(self):
        wet_id = self.work_entry_type.id
        emp = self.employee_fixed

        self.assertEqual(self._split(emp, self.friday, 4.0)[wet_id], [1.0, 4.0])
        self.assertEqual(self._split(emp, self.friday, 2.0)[wet_id], [0.5, 2.0])
        self.assertEqual(self._split(emp, self.monday, 8.0)[wet_id], [1.0, 8.0])
        self.assertEqual(self._split(emp, self.monday, 4.0)[wet_id], [0.5, 4.0])

    def test_variable_calendar(self):
        wet_id = self.work_entry_type.id
        emp = self.employee_variable

        self.assertEqual(self._split(emp, self.friday, 4.0)[wet_id], [1.0, 4.0])
        self.assertEqual(self._split(emp, self.friday, 2.0)[wet_id], [0.5, 2.0])
        self.assertEqual(self._split(emp, self.monday, 8.0)[wet_id], [1.0, 8.0])
        self.assertEqual(self._split(emp, self.monday, 4.0)[wet_id], [0.5, 4.0])
        self.assertEqual(self._split(emp, self.friday_later, 4.0)[wet_id], [1.0, 4.0])

    def test_extra_hours_take_no_day(self):
        public_holiday = self.env.ref('hr_work_entry.l10n_be_work_entry_type_bank_holiday')
        overtime = self.env.ref('hr_work_entry.l10n_be_work_entry_type_overtime_no_onss_horeca')
        version = self.employee_fixed.version_id
        # a public holiday with Horeca overtime keeps its full day, overtime alone counts hours only
        work_data = version._get_work_hours_split_half(self.monday, self.monday + timedelta(days=1), [
            {'version_id': version, 'date': self.monday, 'work_entry_type_id': public_holiday, 'duration': 8.0},
            {'version_id': version, 'date': self.monday, 'work_entry_type_id': overtime, 'duration': 2.0},
            {'version_id': version, 'date': self.monday + timedelta(days=1), 'work_entry_type_id': overtime, 'duration': 3.0},
        ])
        result = {work_entry_type_id: values for (work_entry_type_id, _options), values in work_data.items()}
        self.assertEqual(result[public_holiday.id], [1.0, 8.0])
        self.assertEqual(result[overtime.id], [0, 5.0])
