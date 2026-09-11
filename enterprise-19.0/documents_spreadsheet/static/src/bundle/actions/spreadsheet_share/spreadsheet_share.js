import { Component } from "@odoo/owl";
import { registries } from "@spreadsheet/o_spreadsheet/o_spreadsheet";
import { SpreadsheetShareButton } from "@spreadsheet/components/share_button/share_button";
import { _t } from "@web/core/l10n/translation";

const { topbarComponentRegistry } = registries;

export class DocumentsTopbarShareButton extends Component {
    static template = "spreadsheet_edition.DocumentsTopbarShareButton";
    static components = {
        SpreadsheetShareButton,
    };
    static props = {};
}

topbarComponentRegistry.add("documents_share_button", {
    component: DocumentsTopbarShareButton,
    isVisible: (env) => env.isFrozenSpreadsheet && !env.isFrozenSpreadsheet(),
    sequence: 25,
});

registries.topbarMenuRegistry.addChild("share", ["file"], {
    name: _t("Share"),
    sequence: 30,
    isVisible: (env) => env.onShareSpreadsheet || env.onFreezeAndShareSpreadsheet,
    icon: "o-spreadsheet-Icon.SHARE",
});

registries.topbarMenuRegistry.addChild("share_share", ["file", "share"], {
    name: _t("Share"),
    sequence: 10,
    isVisible: (env) => env.onShareSpreadsheet,
    execute: (env) => env.onShareSpreadsheet(),
});

registries.topbarMenuRegistry.addChild("freeze_and_share", ["file", "share"], {
    name: _t("Freeze and share"),
    sequence: 20,
    isVisible: (env) =>
        env.onFreezeAndShareSpreadsheet && env.isFrozenSpreadsheet && !env.isFrozenSpreadsheet(),
    execute: (env) => env.onFreezeAndShareSpreadsheet(),
});
