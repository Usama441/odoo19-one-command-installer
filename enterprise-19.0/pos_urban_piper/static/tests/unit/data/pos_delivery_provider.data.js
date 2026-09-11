import { patch } from "@web/core/utils/patch";
import { hootPosModels } from "@point_of_sale/../tests/unit/data/generate_model_definitions";
import { models } from "@web/../tests/web_test_helpers";

export class PosDeliveryProvider extends models.ServerModel {
    _name = "pos.delivery.provider";

    _load_pos_data_fields() {
        return [["id", "name", "technical_name"]];
    }
}

patch(hootPosModels, [...hootPosModels, PosDeliveryProvider]);
