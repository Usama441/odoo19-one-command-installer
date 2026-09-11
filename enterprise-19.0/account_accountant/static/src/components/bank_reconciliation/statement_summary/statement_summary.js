import { Component } from "@odoo/owl";

export class BankRecStatementSummary extends Component {
    static template = "account_accountant.BankRecStatementSummary";

    static props = {
        label: { type: String },
        amount: { type: String, optional: true },
        action: { type: Function },
        journalId: { type: Number, optional: true },
        isValid: { type: Boolean, optional: true },
    };
    static defaultProps = {
        isValid: true,
    };
}
