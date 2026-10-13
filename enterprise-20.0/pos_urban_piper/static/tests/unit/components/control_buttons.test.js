import { test, expect, animationFrame } from "@odoo/hoot";
import { mountWithCleanup } from "@web/../tests/web_test_helpers";
import { setupPosEnvForPrepDisplay } from "@pos_enterprise/../tests/unit/utils";
import { definePosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import { ControlButtons } from "@point_of_sale/app/screens/product_screen/control_buttons/control_buttons";
import { getUrbanPiperFilledOrder } from "@pos_urban_piper/../tests/unit/utils";

definePosModels();

test("preset button is disabled for delivery orders", async () => {
    const store = await setupPosEnvForPrepDisplay();
    const order = await getUrbanPiperFilledOrder(store);
    await mountWithCleanup(ControlButtons, { props: {} });

    expect("button:contains(Preset)").toHaveAttribute("disabled");

    // A delivery identifier alone is not enough, the order must come from a delivery platform.
    order.source = false;
    await animationFrame();
    expect("button:contains(Preset)").not.toHaveAttribute("disabled");
});
