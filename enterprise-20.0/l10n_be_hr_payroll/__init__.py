# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import Command

from . import models
from . import report
from . import wizard
from . import controllers


def _l10n_be_hr_payroll_post_install(env):
    env.ref('base.be')._adapt_work_entry_types_to_country()
    env['l10n.be.joint.committee'].search([]).write({'active': False})
    env['hr.salary.rule'].search([('country_id', '=', env.ref('base.be').id)]).write({'active': False})
    env['hr.payroll.structure'].search([('country_id', '=', env.ref('base.be').id)]).write({'active': False})
    (
        env['hr.payroll.warning'].search([('country_id', '=', env.ref('base.be').id)])
        # it asks for the main joint committee, that activates the other warnings
        - env.ref('l10n_be_hr_payroll.hr_payroll_warning_missing_company_setting')
    ).write({'active': False})
    env['hr.salary.rule.category'].search([('country_id', '=', env.ref('base.be').id)]).write({'active': False})
    # secondary benefits are activated on demand, the joint committee ones with their joint committee
    secondary_benefits = env['hr.contract.salary.benefit'].search([('l10n_be_joint_committee_ids', '!=', False)])
    for xmlid in (
        'l10n_be_hr_payroll.l10n_be_transport_temporary_car',
        'l10n_be_hr_payroll.l10n_be_transport_company_bike',
        'l10n_be_hr_payroll.l10n_be_onss_restructuring',
        'l10n_be_hr_payroll.l10n_be_time_in_rnd_benefit',
        'l10n_be_hr_payroll.l10n_be_posted_employees_benefit',
    ):
        secondary_benefits |= env.ref(xmlid)
    secondary_benefits.write({'active': False})

    # the companies created before the belgian payroll still work 40 hours/week
    default_calendar = env.ref('resource.resource_calendar_std', raise_if_not_found=False)
    for company in env['res.company'].search([]).filtered(lambda company: company.country_id == env.ref('base.be')):
        if company.resource_calendar_id != default_calendar or env['hr.payslip'].search_count([('company_id', '=', company.id)], limit=1):
            continue
        calendar_values = company._prepare_resource_calendar_values()
        calendar_values['attendance_ids'] = [Command.clear()] + calendar_values['attendance_ids']
        default_calendar.write(calendar_values)

    belgian_companies_without_work_location = env['res.company'].search([]).filtered(
        lambda company: company.country_id == env.ref('base.be')
        and not env['hr.work.location'].search_count([('company_id', '=', company.id)], limit=1))
    env['hr.work.location'].create([{
        'name': env._('Office'),
        'company_id': company.id,
        'location_type': 'office',
    } for company in belgian_companies_without_work_location])
