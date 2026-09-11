from odoo import Command

from odoo.tests import tagged
from odoo.addons.repair.tests.test_repair import TestRepairCommon


@tagged('post_install', '-at_install')
class TestQualityRepair(TestRepairCommon):

    def test_repair_w_lot_and_quality_check(self):
        """Test quality check creation and flow on repair order"""

        self.env['quality.point'].create({
            'name': 'QP1',
            'measure_on': 'product',
            'picking_type_ids': [Command.set([self.stock_warehouse.repair_type_id.id])],
        })
        repair = self.env['repair.order'].create({
            'product_id': self.product_storable_lot.id,
            'partner_id': self.res_partner_1.id,
        })
        repair.action_generate_serial()
        repair.action_validate()
        # Quality check should be created at repair validation
        qc = repair.quality_check_ids
        lot_1 = repair.lot_id
        self.assertEqual(len(qc), 1)
        self.assertEqual(lot_1.ids, qc.lot_ids.ids)

        # Reset repair lot
        repair.lot_id = False
        self.assertFalse(qc.lot_ids)
        repair.action_repair_start()
        repair.action_generate_serial()
        lot_2 = repair.lot_id
        self.assertNotEqual(lot_1, lot_2)
        self.assertEqual(lot_2.ids, qc.lot_ids.ids)

        # 'Pass' Quality Checks of repair order.
        qc.do_pass()
        self.assertEqual(qc.quality_state, 'pass')
        repair.action_repair_end()
        self.assertEqual(repair.state, 'done')
