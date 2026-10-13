/** @odoo-module */

import { patch } from "@web/core/utils/patch";
import { TicketScreen } from "@point_of_sale/app/screens/ticket_screen/ticket_screen";
import { AlertDialog } from "@web/core/confirmation_dialog/confirmation_dialog";
import { _t } from "@web/core/l10n/translation";

patch(TicketScreen.prototype, {
    //@override
    async onDoRefund() {
        if (this.pos.config.useFiscalPrinter) {
            const order = this.pos.models["pos.order"].getBy("uuid", this.state.selectedOrderUuid);
            // Orders without a printer serial number can only be refunded on the POS config they were created on
            if (!order.it_fiscal_printer_serial_number) {
                const data = await this.pos.data.call("pos.order", "read_pos_config_data", [
                    [["id", "=", order.id]],
                ]);
                const config_data = data[0];
                if (config_data.id != this.pos.config.id) {
                    this.dialog.add(AlertDialog, {
                        body: _t(
                            "This order was created on POS '%s' (ID %s) and must be refunded using the same POS.",
                            config_data.name,
                            config_data.id
                        ),
                        title: _t("Fiscal Printer: Refund not allowed"),
                        confirm: () => {},
                        confirmLabel: _t("Close"),
                    });
                    return;
                }
            }
        }
        await super.onDoRefund(...arguments);
        if (this.pos.config.useFiscalPrinter) {
            this.pos.navigate("PaymentScreen", { orderUuid: this.pos.selectedOrderUuid });
        }
    },
});
