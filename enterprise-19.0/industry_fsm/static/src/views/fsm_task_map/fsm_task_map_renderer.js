import { MapRenderer } from "@web_map/map_view/map_renderer";

import { formatDateTime } from "@web/core/l10n/dates";
import { localization } from "@web/core/l10n/localization";

const { DateTime } = luxon;

export class FsmTaskMapRenderer extends MapRenderer {
    static subTemplates = {
        ...MapRenderer.subTemplates,
        PinListItems: "industry_fsm.FsmTaskMapRenderer.PinListItems",
    };

    getFormattedTime(record) {
        const { planned_date_begin } = record;
        if (!planned_date_begin) {
            return "";
        }
        const format = localization.timeFormat.search("HH") === 0 ? "HH:mm" : "hh:mm A";
        return formatDateTime(
            DateTime.fromSQL(
                record.planned_date_begin,
                { numberingSystem: "latn", zone: "default" }
            ),
            { format: format }
        );
    }
}
