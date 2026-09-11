import { test, describe, expect } from "@odoo/hoot";
import { definePosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import { setupPosEnv } from "@point_of_sale/../tests/unit/utils";

definePosModels();

describe("pos.config", () => {
    test("preparationDisplayCategories", async () => {
        const store = await setupPosEnv();

        expect(store.config.preparationCategories).toEqual(new Set([1, 2]));
        expect(store.config.preparationDisplayCategories).toEqual(new Set([1]));

        store.models["pos.prep.display"].getFirst().category_ids = [];
        expect(store.config.preparationCategories).toEqual(new Set([1, 2, 4, 3, 5]));
        expect(store.config.preparationDisplayCategories).toEqual(
            new Set(store.models["pos.category"].map((pc) => pc.id))
        );
    });
});
