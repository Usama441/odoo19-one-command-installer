import { defineMailModels } from "@mail/../tests/mail_test_helpers";
import { StockMove } from "@mrp_workorder/mrp_display/mrp_record_line/stock_move";
import { expect, test } from "@odoo/hoot";
import { animationFrame } from "@odoo/hoot-mock";
import { proxy } from "@odoo/owl";
import { mountWithCleanup, patchWithCleanup } from "@web/../tests/web_test_helpers";
import { localization } from "@web/core/l10n/localization";

defineMailModels();

function mountStockMove(moveLine) {
    return mountWithCleanup(StockMove, {
        props: {
            clickable: false,
            displayUOM: false,
            isCurrent: false,
            startWorking: () => {},
            record: {
                fields: { quantity: { digits: [16, 2] } },
                data: {
                    product_id: { display_name: "Component" },
                    has_tracking: "none",
                    picked: true,
                    product_uom_qty: 1000,
                    move_line_ids: { records: [moveLine] },
                },
            },
            production: {},
        },
    });
}

test("registered quantity is displayed in full at or above one thousand", async () => {
    const moveLine = proxy({ data: { quantity: 1000, picked: true } });
    await mountStockMove(moveLine);
    patchWithCleanup(localization, { decimalPoint: ".", thousandsSep: ",", grouping: [3, 0] });
    for (const [quantity, displayedQuantity] of [
        [999, "999 / 1000"],
        [1000, "1000"],
        [1001, "1001 / 1000"],
        [1234.56, "1234.56 / 1000"],
    ]) {
        moveLine.data.quantity = quantity;
        await animationFrame();
        expect(".o_mrp_record_line_qty").toHaveText(displayedQuantity);
        expect(".o_line_value.text-danger").toHaveCount(quantity > 1000 ? 1 : 0);
    }
});

test("registered quantity is displayed in full when the decimal separator is a comma", async () => {
    const moveLine = proxy({ data: { quantity: 1000, picked: true } });
    await mountStockMove(moveLine);
    patchWithCleanup(localization, { decimalPoint: ",", thousandsSep: ".", grouping: [3, 0] });
    for (const [quantity, displayedQuantity] of [
        [999.5, "999.5 / 1000"],
        [1000, "1000"],
        [1234.56, "1234.56 / 1000"],
    ]) {
        moveLine.data.quantity = quantity;
        await animationFrame();
        expect(".o_mrp_record_line_qty").toHaveText(displayedQuantity);
        expect(".o_line_value.text-danger").toHaveCount(quantity > 1000 ? 1 : 0);
    }
});
