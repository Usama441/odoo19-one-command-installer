from odoo import models, fields, api, _


class PosPrepOrder(models.Model):
    _inherit = 'pos.prep.order'

    pos_course_id = fields.Many2one('restaurant.order.course')

    @api.model_create_multi
    def create(self, vals_list):
        course_id = self.env.context.get('po_course_id', None)
        if course_id:
            for vals in vals_list:
                if not vals.get('pos_course_id', None):
                    vals['pos_course_id'] = course_id
        return super().create(vals_list)

    @api.model
    def process_order(self, order_id, options={}):
        order = self.env['pos.order'].browse(order_id)

        if options.get('cancelled') or not order.course_ids or not order:
            return super().process_order(order_id, options)

        reload_display = False
        category_ids = []
        course_updated_notifications = []
        fired_course_id = options.get('fired_course_id')

        for course_id in order.course_ids:
            course_lines_uuids = course_id.line_ids.mapped(lambda l: l.uuid)
            course_already_fired = (course_id.fired and
                                    self.env['pos.prep.order'].search([('pos_order_id', '=', order.id)], limit=1))

            def order_line_filer(line_uuid):
                return line_uuid in course_lines_uuids

            changes = order.with_context(ppc_order_line_filter=order_line_filer, po_course_id=course_id.id)._process_preparation_changes(options)

            if changes.get('change'):
                category_ids += course_id.line_ids.product_id.pos_categ_ids.ids
                reload_display = True

            if changes.get('order_added') and course_already_fired:
                course_updated_notifications.append({
                    'category_ids': changes.get('category_ids'),
                    'notification': _("Course %s Updated", str(course_id.index))
                })

        if reload_display or fired_course_id:
            course = self.env['restaurant.order.course'].browse(fired_course_id)
            category_ids += course.line_ids.product_id.pos_categ_ids.ids
            preparation_display = self.env['pos.prep.display']._get_preparation_displays(order, category_ids)
            for display in preparation_display:
                display._send_load_orders_message(sound=True, orderId=order.id)

        if fired_course_id and any(c.id == fired_course_id for c in order.course_ids):
            course = self.env['restaurant.order.course'].browse(fired_course_id)
            category_ids = course.line_ids.product_id.pos_categ_ids.ids
            self._send_notification_to_preparation_displays(order, {
                'category_ids': category_ids,
                'notification': _("Course %s Fired", str(course.index))
            })
        for notification in course_updated_notifications:
            self._send_notification_to_preparation_displays(order, notification)

        return True

    @api.model
    def _send_notification_to_preparation_displays(self, order, data):
        for p_dis in self.env['pos.prep.display']._get_preparation_displays(order, data['category_ids']):
            p_dis._send_notification(data.get('sound'), data.get('notification'))

    @api.depends('pos_order_id.floating_order_name', 'pos_order_id.table_id')
    def _compute_order_name(self):
        super()._compute_order_name()
        for order in self:
            if order.pos_order_id.session_id.config_id.module_pos_restaurant:
                course_name = f" - {_('Course')[0]}{order.pos_course_id.index}" if order.pos_course_id else ''
                if order.pos_order_id.table_id:
                    order.order_name = self._get_table_name(order.pos_order_id.table_id) + course_name
                elif order.pos_order_id.floating_order_name:
                    order.order_name = order.pos_order_id.floating_order_name + course_name
                else:
                    order.order_name = _("Direct Sale")

    @api.model
    def _get_table_name(self, table):
        if not table:
            return ""
        name = f"T{table.table_number}"
        if table.parent_id:
            name += f" &{table.parent_id.table_number}"
        return name
