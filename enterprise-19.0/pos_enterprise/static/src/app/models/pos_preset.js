import { PosPreset } from "@point_of_sale/app/models/pos_preset";
import { patch } from "@web/core/utils/patch";

const { DateTime } = luxon;

patch(PosPreset.prototype, {
    get nextSlot() {
        const dateNow = DateTime.now();
        const sqlDate = dateNow.toFormat("yyyy-MM-dd");
        return Object.values(this.uiState.availabilities[sqlDate]).find(
            (s) => s.datetime > dateNow
        );
    },
});
