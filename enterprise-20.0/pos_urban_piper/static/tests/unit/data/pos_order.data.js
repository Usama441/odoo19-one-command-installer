import { patch } from "@web/core/utils/patch";
import { PosOrder } from "@point_of_sale/../tests/unit/data/pos_order.data";

patch(PosOrder.prototype, {
    order_status_update() {
        return { is_success: true, message: "test message" };
    },

    mark_urbanpiper_prep_order_as_printed() {
        return true;
    },
});
