# Part of Odoo. See LICENSE file for full copyright and licensing details.

from collections import defaultdict
from odoo import fields
from odoo.http import request, route

from odoo.addons.website_sale_renting.controllers.main import WebsiteSaleRenting


class WebsiteSalePlanningRenting(WebsiteSaleRenting):

    @route()
    def renting_product_availabilities(self, product_id, min_date, max_date):
        product_sudo = request.env['product.product'].sudo().browse(product_id).exists()
        result = super().renting_product_availabilities(product_id, min_date, max_date)
        if (
            product_sudo.type == 'service'
            and product_sudo.rent_ok
            and product_sudo.planning_enabled
            and (resources := product_sudo.planning_role_id.filtered('sync_shift_rental').resource_ids)
        ):
            min_date = fields.Datetime.to_datetime(min_date)
            max_date = fields.Datetime.to_datetime(max_date)
            slots_sudo = self.env['planning.slot'].sudo().search([
                ('resource_id', 'in', resources.ids),
                ('start_datetime', '<=', max_date),
                ('end_datetime', '>=', min_date),
            ], order='start_datetime')  # In sudo mode to access to planning slots' fields from eCommerce.
            rented_quantities = defaultdict(int)
            for _resource, slots in slots_sudo.grouped('resource_id').items():
                for slot in slots:
                    rented_quantities[slot.start_datetime] += 1
                    rented_quantities[slot.end_datetime] -= 1
            key_dates = sorted(set(rented_quantities.keys()) | {min_date, max_date})

            availabilities = []
            current_qty_available = len(resources)
            for i in range(1, len(key_dates)):
                start_dt = key_dates[i - 1]
                if start_dt > max_date:
                    break
                current_qty_available -= rented_quantities[start_dt]
                if start_dt >= min_date:
                    availabilities.append({
                        'start': start_dt,
                        'end': key_dates[i],
                        'quantity_available': current_qty_available,
                    })
            result['renting_availabilities'] = availabilities
        return result
