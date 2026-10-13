import { test, expect } from "@odoo/hoot";
import { getUrbanPiperFilledOrder } from "@pos_urban_piper/../tests/unit/utils";
import { definePosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import {
    renderOrderChangeReceipt,
    expectOrderChangeTicket,
} from "@point_of_sale/../tests/unit/receipt_utils";
import { setupPoSEnvForSelfOrderUrbanPiper } from "../utils";

definePosModels();

test("Guest count is hidden for UrbanPiper orders", async () => {
    const store = await setupPoSEnvForSelfOrderUrbanPiper();
    store.config.module_pos_restaurant = true;

    // Hidden for UrbanPiper orders.
    const deliveryOrder = await getUrbanPiperFilledOrder(store);
    const { changes, tickets } = renderOrderChangeReceipt(store, deliveryOrder);
    expect(tickets).toHaveLength(1);
    expect(changes).toHaveLength(1);
    expect(changes[0].order.customer_count).toBe(0);
    expectOrderChangeTicket(tickets[0], { invisibleInDom: ["Guest"] });
});
