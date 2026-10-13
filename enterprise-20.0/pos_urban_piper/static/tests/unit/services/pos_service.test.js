import { test, expect } from "@odoo/hoot";
import { setupPosEnvForPrepDisplay } from "@pos_enterprise/../tests/unit/utils";
import { definePosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import { getUrbanPiperFilledOrder } from "../utils";

definePosModels();

test("onDeleteOrder", async () => {
    const store = await setupPosEnvForPrepDisplay();
    const order = store.addNewOrder();

    order.delivery_identifier = "UP-123";
    let deletedOrder = await store.onDeleteOrder(order);
    expect(deletedOrder).toBe(false);

    order.delivery_identifier = undefined;
    deletedOrder = await store.onDeleteOrder(order);
    expect(deletedOrder).toBe(true);
});

test("customer note is included in the preparation ticket", async () => {
    const store = await setupPosEnvForPrepDisplay();
    const deliveryOrder = await getUrbanPiperFilledOrder(store, {
        general_customer_note: "Never Forget Customer Note!!!",
    });

    let ticketData;
    store.ticketPrinter.generateIframe = (_template, data) => (ticketData = data);
    store.ticketPrinter.setIframeSizeFromPrinter = () => {};
    store.ticketPrinter.generateImage = async () => "mock-image";

    await store._sendDeliveryOrderForPreparation(deliveryOrder);
    expect(ticketData.extra_data.general_customer_note).toBe("Never Forget Customer Note!!!");
});
