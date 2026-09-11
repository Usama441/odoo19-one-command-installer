# Part of Odoo. See LICENSE file for full copyright and licensing details.

from . import models

import logging

from odoo.fields import Date
from dateutil.relativedelta import relativedelta

_logger = logging.getLogger(__name__)


def _generate_payslips(env):
    # Do this only when demo data is activated
    if employee_cecilia := env.ref('base.hr_employee_cecilia', raise_if_not_found=False):

        _generate_period_payslips(env, employee_cecilia, 'monthly', relativedelta(months=1, days=-1))
        employee_karla = env.ref('base.hr_employee_karla', raise_if_not_found=False)
        _generate_period_payslips(env, employee_karla, 'weekly', relativedelta(days=6))
        employee_cesar = env.ref('base.hr_employee_cesar', raise_if_not_found=False)
        _generate_period_payslips(env, employee_cesar, '10_days', relativedelta(days=9))
        employee_xochilt = env.ref('base.hr_employee_xochilt', raise_if_not_found=False)
        _generate_period_payslips(env, employee_xochilt, '14_days', relativedelta(days=13))

        # after many insertions in work_entries, table statistics may be broken.
        # In this case, query plan may be randomly suboptimal leading to slow search
        # Analyzing the table is fast, and will transform a potential ~30 seconds
        # sql time for _mark_conflicting_work_entries into ~2 seconds
        env.cr.execute('ANALYZE hr_work_entry')


def _generate_period_payslips(env, employee, period, period_delta):
    _logger.info('Generating %s Payslips', period.replace("_", " ").title())
    employee.schedule_pay = period

    payrun = env['hr.payslip.run'].create({
        'name': f'{Date.today().year} {period.replace("_", " ").title()} {employee.name}',
        'company_id': env.ref('base.demo_company_mx').id,
    })

    date_from = Date.today() + relativedelta(month=1, day=1)
    last_day_of_year = date_from + relativedelta(years=1, days=-1)
    i = 1
    while date_from <= last_day_of_year:
        date_to = date_from + period_delta

        payslip = env['hr.payslip'].create([{
            'name': f'{period.replace("_", " ").title()} ({i})',
            'date_from': date_from,
            'date_to': date_to,
            'company_id': env.ref('base.demo_company_mx').id,
            'employee_id': employee.id,
            'struct_id': env.ref('l10n_mx_hr_payroll.l10n_mx_regular_pay').id,
            'payslip_run_id': payrun.id,
        }])
        payslip.compute_sheet()
        payslip.action_payslip_done()
        payslip.action_payslip_paid()
        date_from = date_to + relativedelta(days=1)
        i += 1
