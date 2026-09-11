import ast
from collections import defaultdict

from odoo import Command, models
from odoo.tools.float_utils import float_compare


class AccountPayment(models.Model):
    _inherit = "account.payment"

    def action_open_manual_reconciliation_widget(self):
        ''' Open the manual reconciliation widget for the current payment.
        :return: A dictionary representing an action.
        '''
        self.ensure_one()
        action_values = self.env['ir.actions.act_window']._for_xml_id('account_accountant.action_move_line_posted_unreconciled')
        if self.partner_id:
            context = ast.literal_eval(action_values['context'])
            context.update({'search_default_partner_id': self.partner_id.id})
            if self.partner_type == 'customer':
                context.update({'search_default_trade_receivable': 1})
            elif self.partner_type == 'supplier':
                context.update({'search_default_trade_payable': 1})
            action_values['context'] = context
        return action_values

    def button_open_statement_lines(self):
        # OVERRIDE
        """ Redirect the user to the statement line(s) reconciled to this payment.
            :return: An action to open the view of the payment in the reconciliation widget.
        """
        self.ensure_one()

        default_statement_line = self.reconciled_statement_line_ids[-1]
        return self.env['account.bank.statement.line']._action_open_bank_reconciliation_widget(
            extra_domain=[('id', 'in', self.reconciled_statement_line_ids.ids)],
            default_context={
                'create': False,
                'default_st_line_id': default_statement_line.id,
                'default_journal_id': default_statement_line.journal_id.id,
            },
            name=self.env._("Matched Transactions")
        )

    def _get_amls_for_payment_without_move(self):
        valid_payment_states = ['draft', *self.env['account.batch.payment']._valid_payment_states()]
        lines_to_create = []
        for payment in self:
            if payment.state not in valid_payment_states:
                continue

            line2amount = defaultdict(float)

            payment_term_lines = payment.invoice_ids.line_ids.filtered(lambda line: line.display_type == "payment_term" and not line.reconciled).sorted("date")
            remaining = payment.amount_signed
            for line in payment_term_lines:
                if not remaining:
                    break

                if float_compare(payment.amount_signed, 0, payment.currency_id.decimal_places) >= 0:
                    current = min(remaining, line.currency_id._convert(from_amount=line.amount_currency, to_currency=payment.currency_id))
                else:
                    current = max(remaining, line.currency_id._convert(from_amount=line.amount_currency, to_currency=payment.currency_id))
                remaining -= current
                line2amount[line] -= current

            if remaining:
                line2amount[False] -= remaining

            for line, amount in line2amount.items():
                if line:
                    line_to_create = line._get_aml_values(
                        name=payment.name,
                        balance=payment.currency_id._convert(from_amount=amount, to_currency=self.env.company.currency_id),
                        amount_currency=amount,
                        reconciled_lines_ids=[Command.set(line.ids)],
                        payment_lines_ids=[Command.set(payment.ids)],
                    )
                else:
                    partner_account = (
                        payment.partner_id.property_account_payable_id
                        if payment.payment_type == "outbound"
                        else payment.partner_id.property_account_receivable_id
                    )
                    line_to_create = {
                        'name': payment.name,
                        'partner_id': payment.partner_id.id,
                        'account_id': partner_account.id,
                        'currency_id': payment.currency_id.id,
                        'amount_currency': amount,
                        'balance': payment.currency_id._convert(from_amount=amount, to_currency=self.env.company.currency_id),
                        'payment_lines_ids': [Command.set(payment.ids)],
                    }
                lines_to_create.append(line_to_create)
        return lines_to_create
