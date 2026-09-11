import { patch } from "@web/core/utils/patch";
import { hootPosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import { models } from "@web/../tests/web_test_helpers";

export class PosPrepDisplay extends models.ServerModel {
    _name = "pos.prep.display";

    _load_pos_data_fields() {
        return ["id", "category_ids", "write_date"];
    }

    _records = [
        {
            id: 1,
            category_ids: [1],
            write_date: "2025-07-22 15:19:30",
        },
    ];
}

patch(hootPosModels, [...hootPosModels, PosPrepDisplay]);
