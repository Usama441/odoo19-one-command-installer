import { Component, useRef } from "@odoo/owl";
import { BatchPaymentPopover } from "../batch_payment_popover/batch_payment_popover";
import { usePopover } from "@web/core/popover/popover_hook";
import { useBankReconciliation } from "@account_accountant/components/bank_reconciliation/bank_reconciliation_service";

export class BankRecBatchPaymentButton extends Component {
    static template = "account_accountant.BankRecBatchPaymentButton";
    static props = {
        onSelected: Function,
    };

    setup() {
        this.bankReconciliation = useBankReconciliation();
        this.btnRef = useRef("batch-payment-button");
        this.batchPaymentPopover = usePopover(BatchPaymentPopover, {
            position: "bottom",
            closeOnClickAway: true,
        });
    }

    openBatchPaymentsPopOver() {
        if (this.batchPaymentPopover.isOpen) {
            this.batchPaymentPopover.close();
        } else {
            this.batchPaymentPopover.open(this.btnRef.el, {
                batchPayments: this.bankReconciliation.availableBatchPayments?.records,
                onSelected: this.onSelected.bind(this),
            });
        }
    }

    onSelected(batchPaymentId) {
        this.props.onSelected(batchPaymentId);
        this.batchPaymentPopover.close();
    }
}
