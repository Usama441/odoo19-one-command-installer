import { defineModels, fields, onRpc } from "@web/../tests/web_test_helpers";
import { SpreadsheetMixin } from "@spreadsheet/../tests/helpers/data";


class QualityCheckSpreadsheet extends SpreadsheetMixin {
    _name = "quality.check.spreadsheet";

    name = fields.Char();
    check_cell = fields.Char();

    _records = [
        {
            id: 1,
            name: "My quality check spreadsheet",
            spreadsheet_data: "{}",
            check_cell: "A1"
        },
        {
            id: 1111,
            name: "My quality check spreadsheet",
            spreadsheet_data: "{}",
            check_cell: "A1"
        },
    ];

    dispatch_spreadsheet_message() {}
}

onRpc("/spreadsheet/data/quality.check.spreadsheet/*", async function (request) {
    const resId = parseInt(request.url.split('/').at(-1));
    const spreadsheet = this.env["quality.check.spreadsheet"].find((r) =>  r.id === resId);
    return {
        data: JSON.parse(spreadsheet.spreadsheet_data),
        name: spreadsheet.name,
        revisions: [],
        isReadonly: false,
        quality_check_display_name: "The check name",
        quality_check_cell: spreadsheet.check_cell,
    };
}, { pure: true });

export function defineQualitySpreadsheetModels() {
    defineModels({
        QualityCheckSpreadsheet,
    });
}
