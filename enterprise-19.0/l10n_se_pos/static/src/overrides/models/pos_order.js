import { PosOrder } from "@point_of_sale/app/models/pos_order";
import { patch } from "@web/core/utils/patch";

patch(PosOrder.prototype, {
    useBlackBoxSweden() {
        return !!this.config.iface_sweden_fiscal_data_module;
    },
    getSpecificTax(amount) {
        const tax = this.getTaxDetails().find((tax) => tax.tax.amount === amount);

        if (tax) {
            return tax.amount;
        }

        return false;
    },
    waitForPushOrder() {
        var result = super.waitForPushOrder(...arguments);
        result = Boolean(this.useBlackBoxSweden() || result);
        return result;
    },
});
