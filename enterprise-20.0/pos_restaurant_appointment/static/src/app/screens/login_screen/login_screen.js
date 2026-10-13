import { OpeningControlPopup } from "@point_of_sale/app/components/popups/opening_control_popup/opening_control_popup";
import { patch } from "@web/core/utils/patch";
import { ConfirmationDialog } from "@web/core/confirmation_dialog/confirmation_dialog";
import { _t } from "@web/core/l10n/translation";

patch(OpeningControlPopup.prototype, {
    async confirm() {
        if (this.pos.config.module_pos_restaurant) {
            const tableToFix = this.pos.models["restaurant.table"].filter(
                (table) => !table.appointment_resource_id
            );
            if (tableToFix.length > 0) {
                const confirmed = await new Promise((resolve) => {
                    this.pos.dialog.add(ConfirmationDialog, {
                        title: _t("Missing Resources"),
                        body: _t(
                            "Some tables are missing a linked appointment resource. Do you want to fix them now?"
                        ),
                        confirm: () => resolve(true),
                        cancel: () => resolve(false),
                    });
                });
                if (confirmed) {
                    const tableIds = tableToFix.map((table) => table.id);
                    await this.pos.data.callRelated(
                        "restaurant.table",
                        "create_missing_ressources",
                        [tableIds, this.pos.config.id]
                    );
                }
            }
        }
        super.confirm();
    },
});
