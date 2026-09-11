import { BankRecStatementLine } from "@account_accountant/components/bank_reconciliation/statement_line/statement_line";
import { patch } from "@web/core/utils/patch";
import { useState } from "@odoo/owl";

patch(BankRecStatementLine.prototype, {
    setup() {
        super.setup();
        this.availableSaleOrders = useState([]);
    },

    async getAvailableSaleOrders() {
        return {
            records: this.recordData.partner_id.id
                ? await this.orm.search("sale.order", [
                      ["partner_id", "=", this.recordData.partner_id.id],
                  ])
                : [],
        };
    },

    async toggleUnfold() {
        if (!this.isUnfolded) {
            const sales = await this.getAvailableSaleOrders();
            this.availableSaleOrders = sales.records;
        }
        super.toggleUnfold();
    },

    get buttonListProps() {
        return {
            ...super.buttonListProps,
            availableSaleOrders: this.availableSaleOrders,
        };
    },
});
