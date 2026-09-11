# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import models, fields


class HrAttendanceOvertimeLine(models.Model):
    _name = 'hr.attendance.overtime.line'
    _inherit = 'hr.attendance.overtime.line'

    work_entry_type_overtime_id = fields.Many2one('hr.work.entry.type')
