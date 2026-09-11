from odoo import models


class AccountBankStatementLine(models.Model):
    _name = 'account.bank.statement.line'
    _inherit = 'account.bank.statement.line'

    def set_batch_payment_bank_statement_line(self, batch_payment_id):
        self.ensure_one()
        batch_payment = self.env['account.batch.payment'].browse(batch_payment_id)

        amls_domain = self._get_default_amls_matching_domain()
        # Thanks to a constraint, we cannot have a batch that have payment with and without entries.
        # Batch of payment with entries means that reconciled_lines and amls_to_create will have the same length
        # otherwise reconciled_lines is empty
        reconciled_lines, amls_to_create = batch_payment._get_amls_from_batch_payments(amls_domain)
        self._reconcile_payments(batch_payment.payment_ids, amls_to_create, reconciled_lines)

    def delete_reconciled_line(self, move_line_ids):
        """ Deletes the specified move lines from the bank statement line after unreconciling them.

            :param move_line_ids: A list of move line IDs to be deleted.
        """
        self.ensure_one()
        move_lines_to_remove = self.env['account.move.line'].browse(move_line_ids)
        if payments := move_lines_to_remove.payment_lines_ids:
            # Put the payment back to in_process, we don't touch the batch payment itself since it's just an envelope of
            # payments, it could even be removed from the accounting it would be ok
            payments.action_draft()
            payments.action_post()
            # When an invoice is linked to the payment, the move must be put back to draft so that the amount residual
            # is reset and that the payment state of the move is back to in_payment
            if move_linked := payments.invoice_ids:
                move_linked.button_draft()
                move_linked.action_post()

        super().delete_reconciled_line(move_line_ids)
