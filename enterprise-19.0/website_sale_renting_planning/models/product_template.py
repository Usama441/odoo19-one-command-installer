from odoo import models


class ProductTemplate(models.Model):
    _inherit = 'product.template'

    def _search_get_detail(self, website, order, options):
        search_details = super()._search_get_detail(website, order, options)
        if (
            (from_date := options.get('from_date'))
            and (to_date := options.get('to_date'))
            and (
                planning_roles := self.env['planning.role'].sudo().search_fetch(
                    [('sync_shift_rental', '=', True)],
                    ['resource_ids'],
                ))
        ):
            unavailable_resources = self.env['planning.slot'].sudo()._read_group(
                [
                    ('role_id', 'in', planning_roles.ids),
                    ('start_datetime', '<=', to_date),
                    ('end_datetime', '>=', from_date),
                    ('resource_id', '!=', False),
                ],
                [],
                ['resource_id:recordset'],
            )[0][0]
            search_details['base_domain'].append([
                '|',
                ('planning_enabled', '=', False),
                ('planning_role_id', 'in', planning_roles.filtered(lambda r: r.resource_ids - unavailable_resources))
            ])
        return search_details
