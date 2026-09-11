import odoo

from odoo.addons.point_of_sale.tests.common import TestPoSCommon


@odoo.tests.tagged('-at_install', 'post_install')  # Only runs after installation, not at install time
class TestPOSCustomerAccountReconciliation(TestPoSCommon):

    def setUp(self):
        super().setUp()
        self.config = self.basic_config
        self.order_data = [{
            "pos_order_lines_ui_args": [(self.product_a, 1)],
            "payments": [(self.pay_later_pm, 1150)],
            "customer": self.partner_a,
            "is_invoiced": True,
        }, {
            "pos_order_lines_ui_args": [(self.product_a, 1)],
            "payments": [(self.pay_later_pm, 1150)],
            "customer": self.partner_a,
            "is_invoiced": False,
        }, {
            "pos_order_lines_ui_args": [(self.product_a, 1)],
            "payments": [(self.pay_later_pm, 1150)],
            "customer": self.partner_a,
            "is_invoiced": False,
        }, {
            "pos_order_lines_ui_args": [(self.product_a, 1)],
            "payments": [(self.pay_later_pm, 1150)],
            "customer": self.partner_b,
            "is_invoiced": True,
        }, {
            "pos_order_lines_ui_args": [(self.product_a, 1)],
            "payments": [(self.pay_later_pm, 1150)],
            "customer": self.partner_b,
            "is_invoiced": False,
        }]

    def _create_paid_orders(self):
        orders_dict = self._create_orders(self.order_data)
        orders = self.env["pos.order"]
        for order in orders_dict.values():
            order.action_pos_order_paid()
            orders |= order
        return orders

    def _get_unreconciled_moves(self, partner):
        move_lines = self.env['account.move.line'].search([
            ('partner_id', '=', partner.id),
            ('account_id', '=', partner.property_account_receivable_id.id),
            ('reconciled', '=', False)
        ])

        return move_lines

    def _create_settle_order_lines_data(self, due_orders):
        lines = []
        for order in due_orders:
            lines.append({'product': self.config.settle_due_product_id,
                'quantity': 1,
                'settled_order_id': order.id if not order.is_invoiced else False,
                'settled_invoice_id': order.account_move.id if order.is_invoiced else False,
                "qty": 0.0,
                "price_unit": order.amount_paid,
                "price_subtotal": 0.0,
                "price_subtotal_incl": 0.0,
                "price_type": "manual",
                "discount": 0.0,
                "refunded_qty": 0.0,
                "price_extra": 0.0
            })
        return lines

    def _create_settle_order(self, due_orders, is_invoiced=False):
        result = []
        order_data = []
        for partner_id in due_orders.mapped('partner_id'):
            partner_due_orders = due_orders.filtered(lambda o: o.partner_id.id == partner_id.id)
            total_due = sum(order.amount_paid for order in partner_due_orders)
            payments = [(self.bank_pm1, total_due)]
            payments.append((self.pay_later_pm, -total_due))
            order_data.append({
                "pos_order_lines_ui_args": self._create_settle_order_lines_data(
                    partner_due_orders
                ),
                "payments": payments,
                "customer": partner_id,
                "is_invoiced": is_invoiced,
            })
        order_data = [self.create_ui_order_data(**params) for params in order_data]
        for data in order_data:
            data['state'] = 'paid'
            data['amount_paid'] = 0

        order_ids = [order['id'] for order in self.env['pos.order'].sync_from_ui(order_data)['pos.order']]
        for order_id in self.env["pos.order"].browse(order_ids):
            result += order_id

        return result

    def _perform_test_customer_account_payment_is_reconciled(self, is_invoiced):
        session1 = self.open_new_session()
        orders = self._create_paid_orders()
        session1.close_session_from_ui()
        self.assertTrue(self._get_unreconciled_moves(self.partner_a))
        self.assertTrue(self._get_unreconciled_moves(self.partner_b))
        session2 = self.open_new_session()
        self._create_settle_order(orders, is_invoiced)
        session2.close_session_from_ui()
        self.assertFalse(self._get_unreconciled_moves(self.partner_a))
        self.assertFalse(self._get_unreconciled_moves(self.partner_b))

    def test_customer_account_payment_is_reconciled_when_settlement_order_invoiced(self):
        self._perform_test_customer_account_payment_is_reconciled(True)

    def test_customer_account_payment_is_reconciled_when_settlement_order_not_invoiced(self):
        self._perform_test_customer_account_payment_is_reconciled(False)

    def test_customer_account_payment_is_reconciled_when_settlement_on_same_session(self):
        session1 = self.open_new_session()
        orders = self._create_paid_orders()
        self._create_settle_order(orders, False)
        session1.close_session_from_ui()
        self.assertFalse(self._get_unreconciled_moves(self.partner_a))
        self.assertFalse(self._get_unreconciled_moves(self.partner_b))
