import { BankReconciliationService } from "@account_accountant/components/bank_reconciliation/bank_reconciliation_service";
import { patch } from "@web/core/utils/patch";
import { reactive } from "@odoo/owl";

patch(BankReconciliationService.prototype, {
    setup(env, services) {
        super.setup(env, services);
        this.availableBatchPayments = reactive([]);
    },

    async updateAvailableBatchPayments(journalId) {
        this.availableBatchPayments = await this.orm.webSearchRead(
            "account.batch.payment",
            [
                ["state", "!=", "reconciled"],
                ["journal_id", "=", journalId],
            ],
            {
                specification: {
                    id: {},
                    name: {},
                    date: {},
                    currency_id: {},
                    amount_residual: {},
                },
                limit: 5,
            }
        );
    },
});
