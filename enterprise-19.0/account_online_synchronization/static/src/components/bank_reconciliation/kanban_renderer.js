import { patch } from "@web/core/utils/patch";
import { BankRecKanbanRenderer } from "@account_accountant/components/bank_reconciliation/kanban_renderer";

patch(BankRecKanbanRenderer.prototype, {
    async getJournalTotalAmount() {
        const values = await this.orm.call("account.journal", "get_total_journal_amount", [
            this.globalState.journalId,
        ]);
        this.globalState.totalJournalAmount = values.balance_amount;
        this.globalState.journalAvailableBalanceAmount = values.available_balance_amount || "";
    },
});
