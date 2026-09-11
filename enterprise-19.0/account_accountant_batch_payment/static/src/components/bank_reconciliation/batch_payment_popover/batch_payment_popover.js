import { BatchPaymentPopoverLine } from "./batch_payment_popover_line";
import { Component } from "@odoo/owl";
import { SelectCreateDialog } from "@web/views/view_dialogs/select_create_dialog";
import { useOwnedDialogs } from "@web/core/utils/hooks";
import { _t } from "@web/core/l10n/translation";

export class BatchPaymentPopover extends Component {
    static template = "account_accountant.BatchPaymentPopover";
    static props = {
        batchPayments: Array,
        close: { type: Function, optional: true },
        onSelected: Function,
    };
    static components = {
        BatchPaymentPopoverLine,
    };

    setup() {
        this.addDialog = useOwnedDialogs();
    }

    onSelected(batchPaymentId) {
        this.props.onSelected(batchPaymentId);
    }

    searchMore() {
        this.addDialog(SelectCreateDialog, {
            title: _t("Search: Batch payment"),
            noCreate: false,
            multiSelect: false,
            resModel: "account.batch.payment",
            onSelected: async (batchPayment) => {
                this.onSelected(batchPayment[0]);
            },
        });
    }
}
