import { Component } from "@odoo/owl";
import { formatMonetary } from "@web/views/fields/formatters";
import { getCurrency } from "@web/core/currency";
import { useService } from "@web/core/utils/hooks";
const { DateTime } = luxon;

export class BatchPaymentPopoverLine extends Component {
    static template = "account_accountant.BatchPaymentPopoverLine";
    static props = {
        batchPayment: {
            type: Object,
            shape: {
                id: Number,
                date: String,
                name: String,
                amount_residual: Number,
                currency_id: Number,
            },
        },
        onSelect: Function,
    };

    setup() {
        this.action = useService("action");
    }

    onClick() {
        this.props.onSelect();
    }

    onOpenBatchPayment() {
        return this.action.doAction({
            type: "ir.actions.act_window",
            res_model: "account.batch.payment",
            target: "current",
            res_id: this.props.batchPayment.id,
            views: [[false, "form"]],
        });
    }

    get formattedDate() {
        const date = DateTime.fromISO(this.props.batchPayment.date);
        return date.toLocaleString({
            month: "short",
            day: "2-digit",
        });
    }

    get formattedAmount() {
        return formatMonetary(this.props.batchPayment.amount_residual, {
            digits: getCurrency(this.props.batchPayment.currency_id)?.digits,
            currencyId: this.props.batchPayment.currency_id,
        });
    }
}
