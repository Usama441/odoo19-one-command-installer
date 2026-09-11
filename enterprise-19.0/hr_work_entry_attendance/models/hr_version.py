# Part of Odoo. See LICENSE file for full copyright and licensing details.

from collections import defaultdict

from dateutil.relativedelta import relativedelta
from pytz import timezone, utc
from datetime import timedelta

from odoo import api, fields, models
from odoo.tools.intervals import Intervals


class HrVersion(models.Model):
    _inherit = 'hr.version'

    work_entry_source = fields.Selection(
        selection_add=[('attendance', 'Attendances')],
        ondelete={'attendance': 'set default'},
    )
    overtime_from_attendance = fields.Boolean(
        "Extra hours", help="Add extra hours from attendances to the working entries", groups="hr.group_hr_manager")

    def _get_overtime_intervals(self, start_dt, end_dt):
        start_naive = start_dt.replace(tzinfo=None)
        end_naive = end_dt.replace(tzinfo=None)

        overtimes = self.env['hr.attendance.overtime.line'].search([
            ('employee_id', 'in', self.employee_id.ids),
            ('time_start', '<', end_naive),
            ('time_stop', '>', start_naive),
        ])

        res = {}
        for resource, overtimes in overtimes.grouped(
            lambda ot: ot.employee_id.resource_id
        ).items():
            res[resource.id] = Intervals(
                ((
                    max(start_naive, ot.time_start).astimezone(utc),
                    min(end_naive, ot.time_stop).astimezone(utc),
                    ot,
                ) for ot in overtimes),
                keep_distinct=True,
            )
        return res

    def _get_attendance_intervals(self, start_dt, end_dt):
        ##################################
        #   ATTENDANCE BASED CONTRACTS   #
        ##################################
        start_naive = start_dt.replace(tzinfo=None)
        end_naive = end_dt.replace(tzinfo=None)
        attendance_based_contracts = self.filtered(lambda c: c.work_entry_source == 'attendance')
        search_domain = [
            ('employee_id', 'in', attendance_based_contracts.employee_id.ids),
            ('check_in', '<', end_naive),
            ('check_out', '>', start_naive),  # We ignore attendances which don't have a check_out
        ]
        resource_ids = attendance_based_contracts.employee_id.resource_id.ids
        attendances = self.env['hr.attendance'].sudo().search(search_domain) if attendance_based_contracts\
            else self.env['hr.attendance']
        intervals = defaultdict(list)
        for attendance in attendances:
            emp_cal = attendance._get_employee_calendar()
            resource = attendance.employee_id.resource_id
            tz = timezone(emp_cal.tz or resource.tz)    # refer to resource's tz if fully flexible resource (calendar is False)
            check_in_tz = attendance.check_in.astimezone(tz)
            check_out_tz = attendance.check_out.astimezone(tz)
            if attendance.overtime_status == 'refused':
                check_out_tz -= timedelta(hours=attendance.validated_overtime_hours)
            if attendance.employee_id.resource_calendar_id and not attendance.employee_id.resource_calendar_id.flexible_hours:
                lunch_intervals = attendance.employee_id._employee_attendance_intervals(check_in_tz, check_out_tz, lunch=True)
                leaves = emp_cal._leave_intervals_batch(check_in_tz, check_out_tz, None)[False] if emp_cal else Intervals([], keep_distinct=True)
                real_lunch_intervals = lunch_intervals - leaves
                attendance_intervals = Intervals([(check_in_tz, check_out_tz, attendance)]) - real_lunch_intervals
            else:
                attendance_intervals = Intervals([(check_in_tz, check_out_tz, attendance)])
            for interval in attendance_intervals:
                intervals[attendance.employee_id.resource_id.id].append((
                    max(start_dt, interval[0]),
                    min(end_dt, interval[1]),
                    attendance))
        mapped_intervals = {r: Intervals(intervals[r], keep_distinct=True) for r in resource_ids}
        mapped_intervals.update(super()._get_attendance_intervals(
            start_dt, end_dt))

        overtime_intervals = {r: Intervals(keep_distinct=True) for r in mapped_intervals}
        overtime_contracts = self.filtered(lambda c: c.work_entry_source == 'attendance' or c.overtime_from_attendance)
        overtime_intervals.update(overtime_contracts._get_overtime_intervals(start_dt, end_dt))

        work_entry_overtime_intervals = defaultdict(list)
        for r, intervals in overtime_intervals.items():
            for start, end, overtime in intervals:
                if not (overtime.rule_ids.work_entry_type_id and overtime.status == 'approved'):
                    continue
                work_entry_overtime_intervals[r].extend([
                    (start, end, overtime)
                ])

        result = {
            r: (mapped_intervals[r] - overtime_intervals[r])
            | Intervals(work_entry_overtime_intervals[r], keep_distinct=True)
            for r in mapped_intervals
        }
        return result

    def _get_interval_work_entry_type(self, interval):
        self.ensure_one()
        if isinstance(interval[2], self.env['hr.attendance'].__class__):
            return self.env.ref('hr_work_entry.work_entry_type_attendance')
        return super()._get_interval_work_entry_type(interval)

    def _get_valid_leave_intervals(self, attendances, interval):
        self.ensure_one()
        badge_attendances = Intervals([
            (start, end, record) for (start, end, record) in attendances
            if start <= interval[1] and end > interval[0] and isinstance(record, self.env['hr.attendance'].__class__)
        ], keep_distinct=True)
        if badge_attendances:
            leave_interval = Intervals([interval], keep_distinct=True)
            return list(leave_interval - badge_attendances)
        return super()._get_valid_leave_intervals(attendances, interval)

    def _get_real_attendance_work_entry_vals(self, intervals):
        self.ensure_one()
        non_attendance_intervals = [interval for interval in intervals if interval[2]._name not in ['hr.attendance', 'hr.attendance.overtime.line']]
        attendance_intervals = [interval for interval in intervals if interval[2]._name in ['hr.attendance', 'hr.attendance.overtime.line']]
        vals = super()._get_real_attendance_work_entry_vals(non_attendance_intervals)

        employee = self.employee_id
        for interval in attendance_intervals:
            if interval[2]._name == 'hr.attendance':
                work_entry_type = self._get_interval_work_entry_type(interval)
                # All benefits generated here are using datetimes converted from the employee's timezone
                vals += [dict([
                          ('name', "%s: %s" % (work_entry_type.name, employee.name)),
                          ('date_start', interval[0].astimezone(utc).replace(tzinfo=None)),
                          ('date_stop', interval[1].astimezone(utc).replace(tzinfo=None)),
                          ('work_entry_type_id', work_entry_type.id),
                          ('employee_id', employee.id),
                          ('version_id', self.id),
                          ('company_id', self.company_id.id),
                      ] + self._get_more_vals_attendance_interval(interval))]
            elif interval[2]._name == 'hr.attendance.overtime.line':
                overtime_mode = self.ruleset_id.rate_combination_mode
                overtime_line_id = interval[2]
                default_overtime_type = self.env.ref('hr_work_entry.work_entry_type_overtime')
                triggered_rule_work_entry_types = overtime_line_id.rule_ids.mapped('work_entry_type_id') or default_overtime_type

                # Take into account manually encoded duration
                date_start = interval[0].astimezone(utc).replace(tzinfo=None)
                date_stop = interval[0].astimezone(utc).replace(tzinfo=None) + relativedelta(hours=interval[2].manual_duration)
                if overtime_mode == 'max' or len(triggered_rule_work_entry_types) == 1:
                    work_entry_type = max(triggered_rule_work_entry_types, key=lambda w: w.amount_rate)
                    # All benefits generated here are using datetimes converted from the employee's timezone
                    vals += [dict([
                              ('name', "%s: %s" % (work_entry_type.name, employee.name)),
                              ('date_start', date_start),
                              ('date_stop', date_stop),
                              ('work_entry_type_id', work_entry_type.id),
                              ('employee_id', employee.id),
                              ('version_id', self.id),
                              ('company_id', self.company_id.id),
                          ] + self._get_more_vals_attendance_interval(interval))]
                else:
                    for triggered_rule in overtime_line_id.rule_ids:
                        # All benefits generated here are using datetimes converted from the employee's timezone
                        vals += [dict([
                                  ('name', "%s: %s" % (triggered_rule.work_entry_type_id.name, employee.name)),
                                  ('date_start', date_start),
                                  ('date_stop', date_stop),
                                  ('work_entry_type_id', triggered_rule.work_entry_type_id.id),
                                  ('employee_id', employee.id),
                                  ('version_id', self.id),
                                  ('company_id', self.company_id.id),
                              ] + self._get_more_vals_attendance_interval(interval))]
        return vals

    def _get_more_vals_attendance_interval(self, interval):
        vals = super()._get_more_vals_attendance_interval(interval)
        if interval[2]._name == 'hr.attendance':
            vals.append(('attendance_id', interval[2].id))
        if interval[2]._name == 'hr.attendance.overtime.line':
            vals.append(('overtime_id', interval[2].id))
        return vals

    @api.model
    def _get_whitelist_fields_from_template(self):
        return super()._get_whitelist_fields_from_template() + ['overtime_from_attendance']
