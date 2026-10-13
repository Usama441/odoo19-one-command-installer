import { test, expect } from "@odoo/hoot";
import { getFilledOrder, setupPosEnv } from "@point_of_sale/../tests/unit/utils";
import { definePosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import "@l10n_de_pos_cert/app/models/pos_order";
import "@l10n_de_pos_cert/app/services/pos_store";

definePosModels();

const setupFiskalyRetail = async () => {
    const store = await setupPosEnv();
    store.config.module_pos_restaurant = false;
    store.config.is_company_country_germany = true;
    store.config.l10n_de_fiskaly_tss_id = "tss-id|client-id";
    const fiskalyCalls = [];
    store.transactionCall = async (payload, data) => {
        fiskalyCalls.push(data.state);
        return {};
    };
    const syncedTxUuids = [];
    const originalCall = store.data.call.bind(store.data);
    store.data.call = async (model, method, args, kwargs) => {
        if (model === "pos.order" && method === "sync_from_ui") {
            syncedTxUuids.push(args[0][0].l10n_de_fiskaly_transaction_uuid);
        }
        return originalCall(model, method, args, kwargs);
    };
    return { store, fiskalyCalls, syncedTxUuids };
};

test("saved draft order can be deleted in DE Fiskaly retail flow", async () => {
    const { store, fiskalyCalls, syncedTxUuids } = await setupFiskalyRetail();
    const order = store.addNewOrder();
    await store.addLineToCurrentOrder({ product_tmpl_id: store.models["product.template"].get(5) });
    const txUuid = order.l10n_de_fiskaly_transaction_uuid;
    expect(order.isReceiptStarted).toBe(true);
    await store.syncAllOrders({ orders: [order] });
    expect(order.isSynced).toBe(true);

    expect(await store.deleteOrders([order])).toBe(true);
    expect(fiskalyCalls).toEqual(["ACTIVE", "CANCELLED"]);
    expect(syncedTxUuids.at(-1)).toBe(txUuid);
    expect(store.models["pos.order"].get(order.id)).toBeEmpty();
});

test("cancelled receipt is restarted when a product is added again", async () => {
    const { store, fiskalyCalls } = await setupFiskalyRetail();
    const order = store.addNewOrder();
    const product = store.models["product.template"].get(5);
    await store.addLineToCurrentOrder({ product_tmpl_id: product });
    const firstTxUuid = order.l10n_de_fiskaly_transaction_uuid;
    order.removeOrderline(order.lines[0]);
    await store.handleFiskalyCancellation(order);
    expect(order.isReceiptCancelled).toBe(true);

    await store.addLineToCurrentOrder({ product_tmpl_id: product });
    expect(fiskalyCalls).toEqual(["ACTIVE", "CANCELLED", "ACTIVE"]);
    expect(order.isReceiptStarted).toBe(true);
    expect(order.l10n_de_fiskaly_transaction_uuid).not.toBe(firstTxUuid);
});

test("paid order still waits for its receipt transaction in DE Fiskaly flow", async () => {
    const { store } = await setupFiskalyRetail();
    const order = await getFilledOrder(store);
    order.state = "paid";
    store.createTransaction = async () => {
        throw new Error("fiskaly down");
    };

    await expect(store.syncAllOrders({ orders: [order] })).rejects.toThrow("fiskaly down");
    expect(order.isSynced).toBe(false);
});
