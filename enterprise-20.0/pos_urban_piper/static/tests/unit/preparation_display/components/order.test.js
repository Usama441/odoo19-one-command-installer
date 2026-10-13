import { test, expect, mockDate, advanceTime } from "@odoo/hoot";
import { mountWithCleanup } from "@web/../tests/web_test_helpers";
import { definePosPrepDisplayModels } from "@pos_enterprise/../tests/unit/data/generate_model_definitions";
import { setupPosPrepDisplayEnv } from "@pos_enterprise/../tests/unit/utils";
import { createUrbanPiperPrepDisplayTicket } from "@pos_urban_piper/../tests/unit/preparation_display/utils";
import { Order } from "@pos_enterprise/app/components/order/order";

definePosPrepDisplayModels();

test("_computeDuration sets isAlert when 5 minutes or less remain", async () => {
    mockDate("2026-06-08 10:00:00");
    const store = await setupPosPrepDisplayEnv();
    await createUrbanPiperPrepDisplayTicket(store, { prep_time: 25 });
    const comp = await mountWithCleanup(Order, { props: { order: store.filteredOrders[0] } });

    expect(comp._computeDuration()).toBe(25);
    expect(comp.isAlert).toBe(false);

    await advanceTime(19 * 60 * 1000);
    expect(comp._computeDuration()).toBe(6);
    expect(comp.isAlert).toBe(false);

    await advanceTime(60 * 1000);
    expect(comp._computeDuration()).toBe(5);
    expect(comp.isAlert).toBe(true);

    // A late order keeps alerting, its remaining time being clamped to 0.
    await advanceTime(20 * 60 * 1000);
    expect(comp._computeDuration()).toBe(0);
    expect(comp.isAlert).toBe(true);
});
