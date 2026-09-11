from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    car_atn = fields.Float(related="version_id.car_atn", inherited=True, groups="hr_payroll.group_hr_payroll_user")
    wishlist_car_total_depreciated_cost = fields.Float(related="version_id.wishlist_car_total_depreciated_cost", inherited=True, groups="hr_payroll.group_hr_payroll_user")
    company_car_total_depreciated_cost = fields.Float(related="version_id.company_car_total_depreciated_cost", inherited=True, groups="hr_payroll.group_hr_payroll_user")
