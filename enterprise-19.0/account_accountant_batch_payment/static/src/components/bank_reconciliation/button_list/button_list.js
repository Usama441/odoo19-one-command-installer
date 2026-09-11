import { BankRecBatchPaymentButton } from "../batch_payment_button/batch_payment_button";
import { BankRecButtonList } from "@account_accountant/components/bank_reconciliation/button_list/button_list";
import { SelectCreateDialog } from "@web/views/view_dialogs/select_create_dialog";
import { _t } from "@web/core/l10n/translation";
import { patch } from "@web/core/utils/patch";

patch(BankRecButtonList, {
    components: {
        ...BankRecButtonList.components,
        BankRecBatchPaymentButton,
    },
});

patch(BankRecButtonList.prototype, {
    selectBatchPayment() {
        // todo flg: add domain
        this.addDialog(SelectCreateDialog, {
            title: _t("Search: Batch Payment"),
            noCreate: true,
            multiSelect: false,
            resModel: "account.batch.payment",
            onSelected: async (batch) => {
                await this.onSelectBatchPayment(batch[0]);
            },
        });
    },

    async onSelectBatchPayment(batchPaymentId) {
        await this.orm.call(
            "account.bank.statement.line",
            "set_batch_payment_bank_statement_line",
            [this.statementLineData.id, batchPaymentId]
        );
        // delete the selected batch from availableBatchPayments to remove the button
        await this.bankReconciliation.updateAvailableBatchPayments(
            this.statementLineData.journal_id.id
        );
        this.props.statementLine.load();
        this.bankReconciliation.reloadChatter();
    },

    get mobileButtonsToDisplay() {
        const buttons = super.mobileButtonsToDisplay;
        if (this.ui.isSmall) {
            buttons.push({
                label: _t("Batches"),
                action: this.selectBatchPayment.bind(this),
            });
        }
        return buttons;
    },

    get isBatchPaymentsButtonShown() {
        return !!this.bankReconciliation.availableBatchPayments?.length;
    },
});
