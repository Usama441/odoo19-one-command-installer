import logging
import re
import string

from markupsafe import Markup
from itertools import product

from odoo import Command, _, api, fields, models, modules, SUPERUSER_ID
from odoo.exceptions import ValidationError
from odoo.fields import Domain
from odoo.tools import SQL
from odoo.addons.account.tools.structured_reference import is_valid_structured_reference

_logger = logging.getLogger(__name__)


class AccountBankStatement(models.Model):
    _name = 'account.bank.statement'
    _inherit = ['mail.thread.main.attachment', 'account.bank.statement']

    def action_open_bank_reconcile_widget(self):
        self.ensure_one()
        return self.env['account.bank.statement.line']._action_open_bank_reconciliation_widget(
            name=self.name,
            default_context={
                'search_default_statement_id': self.id,
                'search_default_journal_id': self.journal_id.id,
            },
            extra_domain=[('statement_id', '=', self.id)]
        )

    def action_generate_attachment(self):
        ir_actions_report_sudo = self.env['ir.actions.report'].sudo()
        statement_report_action = self.env.ref('account.action_report_account_statement')
        for statement in self:
            statement_report = statement_report_action.sudo()
            content, _content_type = ir_actions_report_sudo._render_qweb_pdf(statement_report, res_ids=statement.ids)
            statement.attachment_ids |= self.env['ir.attachment'].create({
                'name': _("Bank Statement %s.pdf", statement.name) if statement.name else _("Bank Statement.pdf"),
                'type': 'binary',
                'mimetype': 'application/pdf',
                'raw': content,
                'res_model': statement._name,
                'res_id': statement.id,
            })
        return statement_report_action.report_action(docids=self)

    @api.model_create_multi
    def create(self, vals_list):
        statements = super().create(vals_list)
        if not self.env.context.get('skip_pdf_attachment_generation'):
            statements.filtered(lambda statement: statement.is_complete and (
                not statement.attachment_ids
                or not any(attachment.mimetype == 'application/pdf' for attachment in statement.attachment_ids)
            )).action_generate_attachment()

        return statements


class AccountBankStatementLine(models.Model):
    _name = 'account.bank.statement.line'
    _inherit = ['account.bank.statement.line', 'mail.thread.main.attachment']

    # Technical field holding the date of the last time the cron tried to auto-reconcile the statement line. Used to
    # optimize the bank matching process"
    cron_last_check = fields.Datetime()

    bank_statement_attachment_ids = fields.One2many('ir.attachment', compute='_compute_bank_statement_attachment_ids')
    attachment_ids = fields.One2many('ir.attachment', related="move_id.attachment_ids")

    def action_save_close(self):
        return {'type': 'ir.actions.act_window_close'}

    def action_save_new(self):
        action = self.env['ir.actions.act_window']._for_xml_id('account_accountant.action_bank_statement_line_form_bank_rec_widget')
        action['context'] = {'default_journal_id': self.env.context['default_journal_id']}
        return action

    def action_button_draft(self):
        """ This function will allow to reset to draft the move linked to the statement line"""
        return self.move_id.button_draft()

    ####################################################
    # COMPUTE METHODS
    ####################################################

    def _compute_bank_statement_attachment_ids(self):
        attachments = self.env['ir.attachment'].search([
            ('res_model', '=', 'account.bank.statement'),
            ('res_id', 'in', self.statement_id.ids),
            ('res_field', 'in', (False, 'invoice_pdf_report_file')),
        ]).grouped('res_id')

        for st_line in self:
            st_line.bank_statement_attachment_ids = attachments.get(st_line.statement_id.id)

    ####################################################
    # RECONCILIATION PROCESS
    ####################################################

    @api.model
    def _action_open_bank_reconciliation_widget(self, extra_domain=None, default_context=None, name=None, kanban_first=True):
        if default_context is None:
            default_context = {}
        action_reference = 'account_accountant.action_bank_statement_line_transactions' + ('_kanban' if kanban_first else '')
        action = self.env['ir.actions.act_window']._for_xml_id(action_reference)

        default_journal = self.env['account.journal'].browse(
            default_context.get('default_journal_id', default_context.get('search_default_journal_id'))
        )

        action.update({
            'name': name or _("Bank Matching"),
            'context': {**default_context, 'bank_statements_source': default_journal.exists().bank_statements_source},
            'domain': [('state', '!=', 'cancel')] + (extra_domain or []),
        })

        return action

    def action_open_recon_st_line(self):
        self.ensure_one()
        return self.env['account.bank.statement.line']._action_open_bank_reconciliation_widget(
            name=self.name,
            default_context={
                'default_statement_id': self.statement_id.id,
                'default_journal_id': self.journal_id.id,
                'default_st_line_id': self.id,
                'search_default_id': self.id,
            },
        )

    def _cron_try_auto_reconcile_statement_lines(self, batch_size=None, limit_time=0, company_id=None):
        """ Method called by the CRON to reconcile the statement lines automatically.

        :param batch_size: The maximum number of statement lines that could be processed at once by the CRON to avoid
                           a timeout. If specified, the CRON will be trigger again asap using a CRON trigger in case
                           there are still some statement lines to process.
        :param limit_time: Maximum time allowed to run in seconds. 0 if the Cron is allowed to run without time limit.
        :param company_id: Limits the processing to statement lines related to a single company.
        """
        if limit_time and not batch_size:
            _logger.warning("_cron_try_auto_reconcile_statement_lines called with "
                            "limit_time=%r but batch_size=%r won't limit anything", limit_time, batch_size)

        def compute_st_lines_to_reconcile(company_id=None):
            # Find the bank statement lines that are not reconciled and try to reconcile them automatically.
            # The ones that are never be processed by the CRON before are processed first.
            remaining_line_id = None
            limit = batch_size + 1 if batch_size else None
            domain = Domain([
                ('is_reconciled', '=', False),
                ('cron_last_check', '=', False),
            ])
            if company_id is not None:
                domain &= Domain(self.env['account.reconcile.model']._check_company_domain(company_id))
            st_lines = self.search(domain, limit=limit, order="cron_last_check ASC NULLS FIRST, id")
            if batch_size and len(st_lines) > batch_size:
                remaining_line_id = st_lines[batch_size].id
                st_lines = st_lines[:batch_size]
            return st_lines, remaining_line_id

        def is_limit_time_exceeded():
            if batch_size and limit_time:
                # cron limitations only make sense if we have both a batch_size and a limit_time
                return fields.Datetime.now().timestamp() - start_time.timestamp() > limit_time
            # the cron won't be limited, and we'll process all the statement lines never processed before
            return False

        remaining_line_id = None

        start_time = fields.Datetime.now()
        while not is_limit_time_exceeded():
            try:
                # compute the statement lines to reconcile in this batch size
                st_lines, remaining_line_id = compute_st_lines_to_reconcile(company_id=company_id)

                if not st_lines:
                    return

                st_lines._try_auto_reconcile_statement_lines(company_id=company_id)
            except Exception as e:  # noqa: BLE001
                if not modules.module.current_test:
                    self.env.cr.rollback()
                st_lines.cron_last_check = fields.Datetime.now()
                _logger.warning("Error while processing statement lines: %s", e)

            # Commit if we can, in case an issue arises later.
            if not modules.module.current_test:
                self.env.cr.commit()

        if remaining_line_id:
            # If some statement lines couldn't be processed because of the cron limits, manually re-trigger the cron
            self.env.ref('account_accountant.auto_reconcile_bank_statement_line')._trigger()

    def _invoice_matching_post_process(self, st_line, amls):
        # no valid candidates found yet, based on payment_reference, try to match on the following criteria:
        # 1) there is a single invoice with the residual amount matching, for the partner
        # 2) the amount correspond to the discounted amount and the payment date is prior to the discount date
        # 3) there is a small difference, in the allowed error margin (3%)
        candidate_amls = self.env['account.move.line']
        # TODO now that the complex regex stuff is gone, try to remove totally the post process and benchmark when it is done in the SQL query
        for aml in amls:
            if (aml.company_currency_id == st_line.currency_id and (
                    aml.amount_residual == st_line.amount
                    or (aml.discount_balance == st_line.amount and st_line.date <= aml.discount_date)
                    or (aml.amount_residual * 0.97 <= st_line.amount <= aml.amount_residual * 1.03)
                    )
                ) or (
                aml.currency_id == st_line.currency_id and (
                    aml.amount_residual_currency == st_line.amount
                    or (aml.discount_amount_currency == st_line.amount and st_line.date <= aml.discount_date)
                    or (aml.amount_residual_currency * 0.97 <= st_line.amount <= aml.amount_residual_currency * 1.03)
                    )
                ) or (
                aml.currency_id == st_line.foreign_currency_id and (
                    aml.amount_residual_currency == st_line.amount_currency
                    or (aml.discount_amount_currency == st_line.amount_currency and st_line.date <= aml.discount_date)
                    or (aml.amount_residual_currency * 0.97 <= st_line.amount_currency <= aml.amount_residual_currency * 1.03)
                    )
                ):
                candidate_amls += aml

        # if there's more than 1 possible match, we don't reconcile
        if len(candidate_amls) == 1:
            return candidate_amls

    def _try_auto_reconcile_statement_lines(self, company_id=None):
        st_move_ids = self.mapped('move_id').ids
        # The field `cron_last_check` will be written on all processed lines that requires them to be protected against
        # concurrent update to avoid the whole transaction to be rolled back.
        self.lock_for_update()

        # get all the reco models to consider (partner mapping and buttons)
        domain = []
        if company_id is not None:
            domain = Domain(self.env['account.reconcile.model']._check_company_domain(company_id))
        reco_models = self.env['account.reconcile.model'].search(domain)

        # partner mapping
        self.env['account.reconcile.model'].flush_model()
        self.flush_recordset(['journal_id', 'transaction_details', 'payment_ref', 'company_id'])
        self.env.cr.execute(SQL("""
            WITH matching_journal_ids AS (
                    SELECT account_reconcile_model_id,
                           ARRAY_AGG(account_journal_id) AS ids
                      FROM account_journal_account_reconcile_model_rel
                  GROUP BY account_reconcile_model_id
                 )

          SELECT st_line.id AS st_line_id, reco_model.mapped_partner_id
            FROM account_bank_statement_line st_line
       LEFT JOIN LATERAL (
                   SELECT reco_model.id,
                          reco_model.mapped_partner_id
                     FROM account_reconcile_model reco_model
                LEFT JOIN matching_journal_ids ON reco_model.id = matching_journal_ids.account_reconcile_model_id
                    WHERE (matching_journal_ids.ids IS NULL OR st_line.journal_id = ANY(matching_journal_ids.ids))
                      AND reco_model.mapped_partner_id IS NOT NULL
                      AND (
                              (
                                  reco_model.match_label = 'contains'
                                  AND (
                                      st_line.payment_ref ILIKE '%%' || reco_model.match_label_param || '%%'
                                      OR st_line.transaction_details::TEXT ILIKE '%%' || reco_model.match_label_param || '%%'
                                   )
                              ) OR (
                                  reco_model.match_label = 'not_contains'
                                  AND NOT (
                                      st_line.payment_ref ILIKE '%%' || reco_model.match_label_param || '%%'
                                      OR st_line.transaction_details::TEXT ILIKE '%%' || reco_model.match_label_param || '%%'
                                  )
                              ) OR (
                                  reco_model.match_label = 'match_regex'
                                  AND (
                                      st_line.payment_ref ~* reco_model.match_label_param
                                      OR st_line.transaction_details::TEXT ~* reco_model.match_label_param
                                  )
                              )
                          )
                      AND reco_model.id = ANY(%s)
                      AND reco_model.company_id = st_line.company_id
                 ORDER BY reco_model.sequence ASC, reco_model.id ASC
                    LIMIT 1
                 ) AS reco_model ON TRUE
           WHERE st_line.id IN %s
             AND st_line.partner_id IS NULL
             AND reco_model.mapped_partner_id IS NOT NULL
            """, reco_models.ids, tuple(self.ids)))

        for st_line_id, mapped_partner_id in self.env.cr.fetchall():
            st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)  # guarantees batch prefetching if needed
            st_line.partner_id = mapped_partner_id

        # global flushing of tables that should not be updated between the different SQL queries
        self.env['account.account'].flush_model(['account_type', 'active'])
        self.env['account.move'].flush_model(['date', 'amount_total'])
        self.env['account.move.line'].flush_model([
            'ref', 'move_id', 'move_name', 'account_id', 'partner_id', 'company_id',
            'reconciled', 'company_currency_id', 'amount_residual',
            'currency_id', 'amount_residual_currency',
            'discount_date', 'discount_balance', 'discount_amount_currency',
        ])
        self.flush_recordset([
            'move_id', 'partner_id', 'company_id', 'currency_id',
            'amount', 'foreign_currency_id', 'amount_currency', 'payment_ref'
        ])
        self.env['account.payment'].flush_model(['move_id', 'journal_id', 'memo'])

        # get all reconciliable accounts that can be used in the bank reconciliation (invoice & payment matching)
        # note that we:
        #   * include reconciliable accounts that aren't of receivable/payable type
        #   * exclude suspense accounts from bank journals because it wouldn't make sense as we use the suspense accounts to know
        #     when an entry has to be processed. If we reconcile it from another way, it would still be considered as unprocessed
        #     in the reconciliation widget.
        #   * later: exclude the outstanding accounts from bank journals because we don't want an outstanding payment made in journal A
        #     to be match with a transaction in journal B. The outstanding payments are treated separatelly prior to the matching
        account_ids = self.env['account.account'].search([('reconcile', '=', True), ('account_type', 'not in', ('asset_cash', 'liability_credit_card'))])
        account_ids -= self.env['account.journal'].search([('type', 'in', ['bank', 'cash', 'credit'])]).suspense_account_id
        account_ids = account_ids.ids

        # First, try to match invoices and payments using the end to end ID.
        processed_st_line_ids = set()
        st_lines_with_end_to_end_uuid_ids = 'end_to_end_uuid' in self._fields and self.filtered('end_to_end_uuid').ids
        if st_lines_with_end_to_end_uuid_ids:
            self.env.cr.execute(SQL("""
                 -- Query to get either payment amls either invoice/bill amls related to payments which have
                 -- the same end to end uuid of bank statement lines.
                    SELECT st_line.id AS st_line_id,
                           ARRAY_AGG(aml.id ORDER BY aml.id ASC) AS aml_ids
                      FROM account_bank_statement_line st_line
                      JOIN account_payment payment ON st_line.end_to_end_uuid = payment.end_to_end_uuid
                      JOIN account_move_line aml ON (
                              payment.move_id = aml.move_id
                           OR aml.move_id IN (
                              SELECT move_payment_rel.invoice_id
                                FROM account_move__account_payment move_payment_rel
                               WHERE move_payment_rel.payment_id = payment.id
                           )
                      )
                     WHERE aml.move_id NOT IN %(st_move_ids)s
                       AND aml.company_id = st_line.company_id
                       AND aml.reconciled = false
                       AND aml.account_id IN %(account_ids)s
                       AND ((st_line.amount > 0 AND aml.balance > 0) OR (st_line.amount < 0 AND aml.balance < 0))
                       AND aml.parent_state in ('draft', 'posted')
                       AND st_line.id IN %(st_line_ids)s
                  GROUP BY st_line.id
            """, st_move_ids=tuple(st_move_ids), account_ids=tuple(account_ids), st_line_ids=tuple(st_lines_with_end_to_end_uuid_ids)))

            for st_line_id, aml_ids in self.env.cr.fetchall():
                st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)  # Guarantees batch prefetching if needed.
                st_line.with_company(st_line.company_id).with_user(SUPERUSER_ID).set_line_bank_statement_line(aml_ids)
                processed_st_line_ids.add(st_line_id)

            # In case we still have statement lines with end to end uuid and no match, we try to match with single payment
            if st_lines_with_end_to_end_uuid_ids := set(st_lines_with_end_to_end_uuid_ids) - processed_st_line_ids:
                # Get payments without invoices/bills or entries which are matching a bank statement lines
                self.env.cr.execute(SQL("""
                    SELECT st_line.id as st_line_id,
                           payment.id as payment_id
                      FROM account_bank_statement_line st_line
                      JOIN account_payment payment ON st_line.end_to_end_uuid = payment.end_to_end_uuid
                     WHERE st_line.id IN %(st_line_ids)s
                       AND payment.state IN %(payment_state)s
                       AND payment.company_id = st_line.company_id
                       AND (
                             (st_line.amount > 0 AND payment.payment_type = 'inbound')
                           OR (st_line.amount < 0 AND payment.payment_type = 'outbound')
                       )
                """, st_line_ids=tuple(st_lines_with_end_to_end_uuid_ids), payment_state=('draft', *self.env['account.batch.payment']._valid_payment_states())))
                for st_line_id, payment_id in self.env.cr.fetchall():
                    # Guarantees batch prefetching if needed.
                    st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)
                    payment = self.env['account.payment'].browse(payment_id)
                    amls_to_create = payment.with_company(st_line.company_id)._get_amls_for_payment_without_move()
                    st_line.with_company(st_line.company_id)._reconcile_payments(payment, amls_to_create)
                    processed_st_line_ids.add(st_line_id)

        remaining_st_line_ids = list(set(self.ids) - processed_st_line_ids)

        # early return if we already processed everything
        if not remaining_st_line_ids:
            self.write({'cron_last_check': self.env.cr.now()})
            return

        # Then match existing outstanding payments in odoo, on the same journal and with the exact same payment_ref
        processed_st_line_ids = set()
        outstanding_accounts = self.env['account.payment.method.line'].search([]).payment_account_id
        if outstanding_accounts:
            query = SQL("""
                SELECT st_line.id,
                       ARRAY_AGG(word_aml.id) aml_id
                  FROM account_bank_statement_line st_line
          JOIN LATERAL (
                        SELECT DISTINCT ON (aml.id) aml.id, word, aml.ref
                          FROM account_move_line aml
                     LEFT JOIN account_move move ON (move.id = aml.move_id AND move.payment_reference != move.name),
                       LATERAL regexp_split_to_table(
                                  COALESCE(aml.ref, '') || ' - ' ||
                                  COALESCE(aml.move_name, '') || ' - ' ||
                                  COALESCE(move.payment_reference, ''), ' - '
                               ) AS word
                         WHERE (st_line.partner_id IS NULL OR st_line.partner_id = aml.partner_id)
                           AND aml.journal_id = st_line.journal_id
                           AND aml.move_id NOT IN %s
                           AND aml.reconciled = false
                           AND aml.account_id IN %s
                           AND aml.company_id = st_line.company_id
                           AND ((st_line.amount > 0 AND aml.balance > 0) OR (st_line.amount < 0 AND aml.balance < 0))
                           AND (aml.parent_state IN ('draft', 'posted'))
                           AND st_line.id IN %s
                           AND (
                                length(word) > 5 AND st_line.payment_ref ILIKE '%%' || word || '%%'
                               )
                       ) word_aml ON TRUE
              GROUP BY st_line.id
                HAVING COUNT(*) = 1
            """, tuple(st_move_ids), tuple(outstanding_accounts.ids), tuple(remaining_st_line_ids))
            self.env.cr.execute(query)
            for st_line_id, aml_id in self.env.cr.fetchall():
                st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)  # guarantees batch prefetching if needed
                st_line.set_line_bank_statement_line(aml_id)
                if st_line.currency_id.is_zero(st_line.amount_residual):
                    processed_st_line_ids.add(st_line.id)
        remaining_st_line_ids = set(self.ids) - processed_st_line_ids

        # early return if we already processed everything
        if not remaining_st_line_ids:
            self.write({'cron_last_check': fields.Datetime.now()})
            return

        # Then try to match invoices and payments where we can't be wrong, using the statement lines payment_ref
        # At this point, we're not trying to search for outstanding payments anymore
        account_ids = list(set(account_ids) - set(outstanding_accounts.ids))
        query = SQL("""
                SELECT st_line.id,
                       ARRAY_AGG(word_aml.id) aml_ids,
                       SUM(word_aml.amount_residual),
                       word_aml.word matching_word
                  FROM account_bank_statement_line st_line
          JOIN LATERAL (
                        SELECT aml.id, word, aml.ref, aml.amount_residual
                          FROM account_move_line aml
                     LEFT JOIN account_move move ON (move.id = aml.move_id AND move.payment_reference != move.name),
                       LATERAL regexp_split_to_table(
                                  COALESCE(aml.ref, '') || ' - ' ||
                                  COALESCE(aml.move_name, '') || ' - ' ||
                                  COALESCE(move.payment_reference, ''), ' - '
                               ) AS word
                         WHERE (st_line.partner_id IS NULL OR st_line.partner_id = aml.partner_id)
                           AND aml.move_id NOT IN %s
                           AND aml.reconciled = false
                           AND aml.account_id IN %s
                           AND aml.company_id = st_line.company_id
                           AND aml.currency_id = COALESCE(st_line.foreign_currency_id, st_line.currency_id)
                           AND ((st_line.amount > 0 AND aml.balance > 0) OR (st_line.amount < 0 AND aml.balance < 0))
                           AND (aml.parent_state IN ('draft', 'posted'))
                           AND st_line.id IN %s
                           AND (
                                length(word) > 5 AND st_line.payment_ref ILIKE '%%' || word || '%%'
                               )
                       ) word_aml ON TRUE
              GROUP BY st_line.id, matching_word
                HAVING COUNT(*) = 1
        """, tuple(st_move_ids), tuple(account_ids), tuple(remaining_st_line_ids))
        self.env.cr.execute(query)

        st_lines_refs = {}
        to_process = {}

        def is_properly_surrounded(text, substring):
            """
            Definition of what a valid matching word can be: any string, containing whitespaces or not, surrounded by
            start/end of line, whitespace, or punctuation in ['.', ';', ',', '?', '!'].
            """
            # Escape substring for regex safety
            sub_escaped = re.escape(substring)
            # Allowed delimiters: start (^), end ($), whitespace (\s), or [. ; , ? !]
            pattern = rf"(^|[\s\.;,?!]){sub_escaped}($|[\s\.;,?!])"
            return re.search(pattern, text) is not None

        # make sure that a match on payment_ref can't be used to match several distinct aml, even if we are sure the same ref can't
        # be found twice because of the HAVING COUNT(*) = 1, we still need to exclude cases where one ref is included in another.
        for st_line_id, aml_id, aml_amount_residual, matching_word in self.env.cr.fetchall():
            st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)  # guarantees batch prefetching if needed
            # ignore matching words that aren't complete words (not delimited per spaces or punctuation). Doing that in post
            # process rather than in the query itself because the SQL regex operations can't use the index
            if not is_properly_surrounded(st_line.payment_ref, matching_word):
                continue
            to_process[st_line_id, matching_word] = [(aml_id, aml_amount_residual)]
            for word in st_lines_refs.get(st_line_id, []):
                if word in matching_word or matching_word in word:
                    del to_process[st_line_id, matching_word]
                    del to_process[st_line_id, word]
            if st_line_id not in st_lines_refs:
                st_lines_refs[st_line_id] = []
            st_lines_refs[st_line_id].append(matching_word)

        ref_amls_sum = {}
        for key, to_process_list in to_process.items():
            st_line_id, matching_word = key
            st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)  # guarantees batch prefetching if needed
            for aml_id, aml_amount_residual in to_process_list:
                # Exclude move lines to prevent reconciliation when the total residual exceeds the statement line amount
                if st_line_id in ref_amls_sum:
                    if ref_amls_sum[st_line_id] <= 0:
                        continue
                    ref_amls_sum[st_line_id] -= aml_amount_residual
                else:
                    ref_amls_sum[st_line_id] = st_line.amount - aml_amount_residual
                st_line.with_user(SUPERUSER_ID).set_line_bank_statement_line(aml_id)
                if st_line.currency_id.is_zero(st_line.amount_residual):
                    processed_st_line_ids.add(st_line.id)
        remaining_st_line_ids -= processed_st_line_ids

        # early return if we already processed everything
        if not remaining_st_line_ids:
            self.write({'cron_last_check': self.env.cr.now()})
            return

        # At this point, we don't try anymore to find a matching payment for statement lines without partner_id that haven't
        # yet found a counterpart based on the communication. This would be too risky to reconcile only based on the amounts.
        query = SQL("""
                SELECT st_line.id AS st_line_id,
                       ARRAY_AGG(aml.id ORDER BY aml.id ASC) AS all_aml_ids,
                       SUM(aml.amount_residual) AS total_residual
                  FROM account_bank_statement_line st_line
                  JOIN account_move_line aml ON (st_line.partner_id = aml.partner_id AND aml.company_id = st_line.company_id)
                  JOIN account_move move ON aml.move_id = move.id
                 WHERE st_line.partner_id IS NOT NULL
                   AND aml.move_id NOT IN %s
                   AND aml.reconciled = false
                   AND aml.account_id IN %s
                   AND ((st_line.amount > 0 AND aml.balance > 0) OR (st_line.amount < 0 AND aml.balance < 0))
                   AND (aml.parent_state IN ('draft', 'posted'))
                   AND st_line.id IN %s

              GROUP BY st_line.id
        """, tuple(st_move_ids), tuple(account_ids), tuple(remaining_st_line_ids))
        self.env.cr.execute(query)

        # process then remove matched statement lines
        for st_line_id, all_aml_ids, total_residual in self.env.cr.fetchall():
            st_line = self.browse(st_line_id).with_prefetch(self._prefetch_ids)  # guarantees batch prefetching if needed
            if total_residual == st_line.amount:
                # the total open amount for the partner equals the paid amount
                st_line.with_user(SUPERUSER_ID).set_line_bank_statement_line(all_aml_ids)
            elif all_aml_ids:
                amls = self.env['account.move.line'].browse(all_aml_ids)
                candidate_amls = self._invoice_matching_post_process(st_line, amls)
                if candidate_amls:
                    st_line.with_user(SUPERUSER_ID).set_line_bank_statement_line(candidate_amls.ids)

            if st_line.currency_id.is_zero(st_line.amount_residual):
                processed_st_line_ids.add(st_line.id)

        remaining_st_line_ids -= processed_st_line_ids

        # early return if we already processed everything
        if not remaining_st_line_ids:
            self.write({'cron_last_check': self.env.cr.now()})
            return

        # try to apply reco models on the remaining statement lines
        remaining_st_lines = self.browse(list(remaining_st_line_ids)).with_prefetch(self._prefetch_ids)
        reco_models._apply_reconcile_models(remaining_st_lines)

        self.write({'cron_last_check': self.env.cr.now()})

    def _retrieve_partner(self):
        if not (lines_without_partner := self.filtered(lambda stl: not stl.partner_id)):
            return

        self.env.flush_all()
        retrieve_partner_by_account_query = SQL("""
            SELECT ARRAY_AGG(DISTINCT partner_bank.partner_id) FILTER (WHERE partner_bank.company_id::TEXT = ANY(STRING_TO_ARRAY(company.parent_path, '/'))) AS account_matching_partner_with_company,
                   ARRAY_AGG(DISTINCT partner_bank.partner_id) FILTER (WHERE partner_bank.company_id::TEXT = ANY(STRING_TO_ARRAY(company.parent_path, '/')) AND partner.active) AS account_matching_active_partner_with_company,
                   ARRAY_AGG(DISTINCT partner_bank.partner_id) FILTER (WHERE partner_bank.company_id IS NULL) AS account_matching_partner_without_company,
                   ARRAY_AGG(DISTINCT partner_bank.partner_id) FILTER (WHERE partner_bank.company_id IS NULL AND partner.active) AS account_matching_active_partner_without_company,
                   st_line.id AS st_line_id
              FROM res_partner_bank partner_bank
              JOIN account_bank_statement_line st_line ON partner_bank.sanitized_acc_number ILIKE '%%' || NULLIF(REGEXP_REPLACE(st_line.account_number, '\\W+', '', 'g'), '') || '%%'
              JOIN res_company company ON company.id = st_line.company_id
              JOIN res_partner partner ON partner.id = partner_bank.partner_id
             WHERE st_line.id IN %(st_line_ids)s
          GROUP BY st_line.id
        """,
             st_line_ids=tuple(lines_without_partner.ids),
        )
        retrieve_partner_by_name_query = SQL("""
            SELECT ARRAY_AGG(DISTINCT partner.id) FILTER (WHERE partner.complete_name ILIKE st_line.partner_name AND partner.company_id::TEXT = ANY(STRING_TO_ARRAY(company.parent_path, '/'))) AS full_name_matching_partner_with_company,
                   ARRAY_AGG(DISTINCT partner.id) FILTER (WHERE partner.complete_name ILIKE st_line.partner_name AND partner.company_id IS NULL) AS full_name_matching_partner_without_company,
                   ARRAY_AGG(DISTINCT partner.id) FILTER (WHERE partner.complete_name ILIKE '%%' || st_line.partner_name || '%%' AND partner.company_id::TEXT = ANY(STRING_TO_ARRAY(company.parent_path, '/'))) AS partial_name_matching_partner_with_company,
                   ARRAY_AGG(DISTINCT partner.id) FILTER (WHERE partner.complete_name ILIKE '%%' || st_line.partner_name || '%%' AND partner.company_id IS NULL) AS partial_name_matching_partner_without_company,
                   st_line.id AS st_line_id
              FROM res_partner partner
              JOIN account_bank_statement_line st_line ON partner.complete_name ILIKE '%%' || NULLIF(TRIM(st_line.partner_name), '') || '%%'
              JOIN res_company company ON company.id = st_line.company_id
             WHERE partner.parent_id IS NULL
               AND st_line.id IN %(st_line_ids)s
          GROUP BY st_line.id
        """,
             st_line_ids=tuple(lines_without_partner.ids),
        )
        self.env.cr.execute(retrieve_partner_by_account_query)
        account_query_result = self.env.cr.dictfetchall()
        self.env.cr.execute(retrieve_partner_by_name_query)
        name_query_result = self.env.cr.dictfetchall()

        bank_account_matching = {line['st_line_id']: {
            'account_matching_partner_with_company': line['account_matching_partner_with_company'] or [],
            'account_matching_active_partner_with_company': line['account_matching_active_partner_with_company'] or [],
            'account_matching_partner_without_company': line['account_matching_partner_without_company'] or [],
            'account_matching_active_partner_without_company': line['account_matching_active_partner_without_company'] or [],
        } for line in account_query_result}

        partner_name_matching = {line['st_line_id']: {
            'full_name_matching_partner_with_company': line['full_name_matching_partner_with_company'] or [],
            'full_name_matching_partner_without_company': line['full_name_matching_partner_without_company'] or [],
            'partial_name_matching_partner_with_company': line['partial_name_matching_partner_with_company'] or [],
            'partial_name_matching_partner_without_company': line['partial_name_matching_partner_without_company'] or [],
        } for line in name_query_result}

        partner_names = lines_without_partner.filtered(lambda line: line.partner_name).mapped('partner_name')
        partners_from_previous_st_line = {}
        if partner_names:
            # In case we don't find the partner with the above conditions, we will retrieve it
            # from existing statement lines
            retrieve_partner_from_st_line_query = SQL("""
                WITH st_lines AS (
                    SELECT st_line.partner_id AS partner_id,
                           st_line.partner_name AS partner_name,
                           st_line.company_id as company_id,
                           ROW_NUMBER() OVER (PARTITION BY st_line.partner_name ORDER BY st_line.id DESC) AS row_number
                      FROM account_bank_statement_line st_line
                     WHERE st_line.is_reconciled = TRUE
                       AND st_line.partner_name = ANY (%(partner_names)s)
                       AND st_line.company_id IN %(company_ids)s
                  GROUP BY st_line.id
                  ORDER BY st_line.id DESC
                )
                SELECT MIN(partner_id) AS partner_id,
                       ARRAY_AGG(DISTINCT company_id) as company_ids,
                       partner_name
                  FROM st_lines
                 WHERE st_lines.row_number <= 3
              GROUP BY partner_name
                HAVING COUNT(DISTINCT partner_id) = 1
            """,
                partner_names=partner_names,
                company_ids=(*self.company_id.ids, None),
            )
            self.env.cr.execute(retrieve_partner_from_st_line_query)
            query_res_lines = self.env.cr.dictfetchall()
            partners_from_previous_st_line = {
                res_line['partner_name']: {
                    'partner_id': res_line['partner_id'],
                    'company_ids': res_line['company_ids'],
                }
                for res_line in query_res_lines
            }

        for st_line in lines_without_partner:
            # Retrieve the partner from the bank account.
            if st_line.account_number and st_line.id in bank_account_matching:
                if len(partner := bank_account_matching[st_line.id]['account_matching_partner_with_company']) == 1:
                    # First match if company match and partner is active
                    st_line.partner_id = partner[0]
                elif len(partner := bank_account_matching[st_line.id]['account_matching_active_partner_with_company']) == 1:
                    # Second match if company match and partner is inactive
                    st_line.partner_id = partner[0]
                elif len(partner := bank_account_matching[st_line.id]['account_matching_partner_without_company']) == 1:
                    # Third match if company doesn't match and partner is active
                    st_line.partner_id = partner[0]
                elif len(partner := bank_account_matching[st_line.id]['account_matching_active_partner_without_company']) == 1:
                    # Fourth match if company doesn't match and partner is inactive
                    st_line.partner_id = partner[0]

            # Retrieve the partner from the partner name.
            if st_line.partner_name:
                if st_line.id in partner_name_matching:
                    if len(partner := partner_name_matching[st_line.id]['full_name_matching_partner_with_company']) == 1:
                        # First match if partner name full match and company match
                        st_line.partner_id = partner[0]
                    elif len(partner := partner_name_matching[st_line.id]['full_name_matching_partner_without_company']) == 1:
                        # Second match if partner name full match and company doesn't
                        st_line.partner_id = partner[0]
                    elif len(partner := partner_name_matching[st_line.id]['partial_name_matching_partner_with_company']) == 1:
                        # Third match if partner name partially match and company match
                        st_line.partner_id = partner[0]
                    elif len(partner := partner_name_matching[st_line.id]['partial_name_matching_partner_without_company']) == 1:
                        # Fourth match if partner name partially match and company doesn't
                        st_line.partner_id = partner[0]

                if not st_line.partner_id and st_line.partner_name in partners_from_previous_st_line:
                    # Last check, if there is no partner yet, try to match with previous statement lines.
                    match_partner = partners_from_previous_st_line[st_line.partner_name]
                    if st_line.company_id.id in match_partner['company_ids']:
                        st_line.partner_id = match_partner['partner_id']

    def _action_manual_reco_model(self, reco_model_id):
        self.move_id.line_ids.filtered(lambda x: x.account_id == x.move_id.journal_id.suspense_account_id).reconcile_model_id = reco_model_id

    def _get_counterpart_aml(self, open_balance, open_amount_currency, is_same_currency):
        """ Generates a counterpart account move line based on the given open balance.

            :param open_balance: The open balance amount that will be used to create the counterpart account move line.
            :returns: A dictionary containing the values to create a counterpart account move line, with
                     keys like "name", "account_id", "amount_currency", and "currency_id".
        """
        self.ensure_one()
        currency = self.foreign_currency_id or self.currency_id or self.journal_id.currency_id or self.company_id.currency_id
        return {
            'name': self.payment_ref,
            'account_id': self.journal_id.suspense_account_id.id,
            'balance': -open_balance,
            'currency_id': currency.id,
            'amount_currency': -open_amount_currency if is_same_currency else currency.round(-open_balance * currency.with_company(self.company_id).rate),
        }

    def _get_partner_id(self, lines_to_add_partner_ids):
        """ Determines the appropriate partner ID based on the set of partner IDs
            passed to it.

            :param lines_to_add_partner_ids: A set of partner IDs to evaluate.
            :returns: The partner ID if there is exactly one unique partner ID, the current
                      partner ID if the set is empty, or `None` if there are multiple partner IDs.

        """
        self.ensure_one()
        if len(lines_to_add_partner_ids) == 1:
            return lines_to_add_partner_ids.pop()
        if len(lines_to_add_partner_ids) == 0:
            return self.partner_id.id
        return None

    def _set_move_line_to_statement_line_move(self, lines_to_set, lines_to_add):
        """ Updates the bank statement line by setting the provided move lines
            (`lines_to_set`) and adding new move lines (`lines_to_add`). It also handles creating
            a counterpart move line if necessary and associates the correct partner and bank account
            details.

            :param lines_to_set: A recordset of move lines that are already associated
                                 with the bank statement line.
            :param lines_to_add: A list of dictionaries representing the move lines
                                 to be added to the bank statement line.
        """
        self.ensure_one()

        lines_to_add_balance = sum(line['balance'] for line in lines_to_add)
        lines_commands = [Command.set(lines_to_set.ids)] + [Command.create(line_to_add) for line_to_add in lines_to_add]

        open_balance = sum(lines_to_set.mapped('balance')) + lines_to_add_balance
        if not self.company_currency_id.is_zero(open_balance):
            if not self.foreign_currency_id:
                lines_to_add_amount_currency = sum(line['amount_currency'] for line in lines_to_add)
                open_amount_currency = sum(lines_to_set.mapped('amount_currency')) + lines_to_add_amount_currency
                is_same_currency = len(lines_to_set.currency_id) == 1 and all(line['currency_id'] == lines_to_set.currency_id.id for line in lines_to_add)
            else:
                liquidity_lines, _suspense_lines, _other_lines = self._seek_for_lines()
                lines_to_add_amount_currency = sum(line['amount_currency'] for line in lines_to_add)
                open_amount_currency = self.amount_currency + sum((lines_to_set - liquidity_lines).mapped('amount_currency')) + lines_to_add_amount_currency
                # We know that the liquidity is in foreign so
                is_same_currency = len(lines_to_set.currency_id) == 1 and all(line['currency_id'] == self.foreign_currency_id.id for line in lines_to_add)
            lines_commands.append(Command.create(
                self._get_counterpart_aml(open_balance, open_amount_currency, is_same_currency)
            ))
        move = self.move_id.with_context(force_delete=True, skip_readonly_check=True)
        move.line_ids = lines_commands
        partner_id = self._get_partner_id({line['partner_id'] for line in lines_to_add if line.get('partner_id')})
        partner = self.env['res.partner'].browse(partner_id)
        if partner:
            # To avoid "Incompatible companies on records" error, make sure the user is linked to a main company.
            allowed_companies = partner.company_id.root_id
            if len(lines_to_set.company_id) == 1:
                # Or the user is linked to the st_line's company.
                allowed_companies |= lines_to_set.company_id
            # Or the user is not linked to any company.
            if not partner.company_id or partner.company_id in allowed_companies:
                move.line_ids.filtered(lambda line: not line.partner_id).partner_id = partner

        # Create missing partner bank if necessary.
        if self.account_number and self.partner_id:
            self.with_context(
                skip_account_move_synchronization=True,
                skip_readonly_check=True,
            ).partner_bank_id = self._find_or_create_bank_account()

    def _add_move_line_to_statement_line_move(self, lines_to_add):
        """ Adds move lines to the bank statement line and updates the reconciliation.

            :param lines_to_add: A list of move line values to be added to the bank statement line.
        """
        self.ensure_one()
        liquidity_lines, _suspense_lines, other_lines = self._seek_for_lines()
        self._set_move_line_to_statement_line_move(liquidity_lines + other_lines, lines_to_add)

    def set_partner_bank_statement_line(self, partner_id):
        """ Sets the partner for the bank statement line.

            :param partner_id: The ID of the partner to set on the bank statement line.
        """
        if self.partner_name:
            st_lines = self.search([('journal_id', '=', self.journal_id.id), ('partner_name', '=', self.partner_name), ('is_reconciled', '=', False), ('partner_id', '=', False)])
        else:
            st_lines = self

        (st_lines - self).move_id._track_set_author(self.env.ref('base.partner_root'))
        st_lines.with_context(force_delete=True, skip_readonly_check=True).partner_id = partner_id
        st_lines._try_auto_reconcile_statement_lines()

    def set_account_bank_statement_line(self, aml_id, account_id):
        """ Sets the specified account to the given account move line.
            Also creates a reco model for fees for this journal and this account if it's in the 3% range
            Also can delete or try to create new reco model depending on the pattern and if a model is created, returns
            the any unreconciled statement lines that can now use the new rule for matching for the JS to reload them.

            :param aml_id: The ID of the account move line to update.
            :param account_id: The ID of the account to set on the specified account move line.
            :return: The recordset of unreconciled statement lines that can now use the new rule for matching, if created.
        """
        self.ensure_one()
        self._create_account_model_fee(account_id)
        account_move_line = self.line_ids.filtered(lambda line: line.id == aml_id)
        account_move_line.account_id = account_id
        account_move_line.move_id._compute_checked()  # to add to compute dependencies

        if account_move_line.account_id.account_type in {'asset_receivable', 'liability_payable'}:
            return self.env['account.bank.statement.line']

        self._handle_reconciliation_rule(account_move_line, account_id)
        new_rule = self._check_and_create_reconciliation_rule(account_id, self.company_id.id)

        if self.env.context.get('account_default_taxes') and self.env['account.account'].browse(account_id).tax_ids:
            self._recompute_tax_lines()

        if new_rule:
            return self.env['account.bank.statement.line'].search([
                ('journal_id', '=', self.journal_id.id),
                ('is_reconciled', '=', False),
                ('move_id.line_ids.reconcile_model_id', '=', new_rule.id),
            ])
        return self.env['account.bank.statement.line']

    def _handle_reconciliation_rule(self, aml, account_id):
        # If a rule has been created by Odoo and is recommended to the user but another account is chosen, the rule
        # should be deleted.
        should_delete_rule = (
            aml.reconcile_model_id
            and aml.reconcile_model_id.create_uid.id == SUPERUSER_ID
            and account_id not in aml.reconcile_model_id.line_ids.account_id.ids
        )
        if should_delete_rule:
            aml.reconcile_model_id.sudo().unlink()

    def _check_and_create_reconciliation_rule(self, account_id, company_id):
        """Checks if a reconciliation rule exists for the given account and company. If not, attempts to create one
        based on previous statement line patterns.

        :param account_id: ID of the account to check for rules
        :param company_id: ID of the company
        :return: The newly created reconciliation rule if created, None otherwise
        """
        bank_stmt_line_domain = [
            ('company_id', '=', company_id),
            ('journal_id', '=', self.journal_id.id),
            ('payment_ref', '!=', False),
            ('move_id.line_ids.account_id', '=', account_id),
            ('move_id.line_ids.reconcile_model_id', '=', False),
        ]
        previous_statement_lines = self.env['account.bank.statement.line'].search(
            bank_stmt_line_domain, limit=5, order='internal_index desc'
        )
        if len(previous_statement_lines) <= 1:
            return None

        # removing the statement lines from previous statement lines which are already eligible for one of the reco model
        # but reco model does not applied to it yet, because we want to allow multiple reco model with same account for different payment ref
        existing_reco_models = self.env['account.reconcile.model'].search([
            ('company_id', '=', company_id),
            ('line_ids.account_id', '=', account_id),
            ('match_journal_ids', '=', self.journal_id.ids),
            ('match_label', '=', 'match_regex'),
            ('match_label_param', '!=', False),
        ])
        for reco_model in existing_reco_models:
            pattern = re.compile(reco_model.match_label_param, re.IGNORECASE)
            previous_statement_lines = previous_statement_lines.filtered(lambda sl: sl.payment_ref and not pattern.search(sl.payment_ref))
            if len(previous_statement_lines) <= 1:
                return None

        rule_data = self._prepare_reconciliation_rule_data(previous_statement_lines, account_id)
        if rule_data.get('common_substring'):
            return self._create_reconciliation_rule(rule_data)
        return None

    def _prepare_reconciliation_rule_data(self, statement_lines, account_id):
        """Prepares data for reconciliation rule creation."""
        payment_refs = [line.payment_ref for line in statement_lines]
        common_substring = self._get_common_substring(payment_refs)
        if not common_substring:
            return {}
        account = self.env['account.account'].browse(account_id)

        return {
            'name': self._get_reconciliation_model_name(account),
            'common_substring': common_substring,
            'account': account,
            'partner_ids': statement_lines.partner_id.ids if len(statement_lines.partner_id.ids) == 1 else [],
        }

    @api.model
    def _get_reconciliation_model_name(self, account):
        copied_count = self.env['account.reconcile.model'].search_count([
            ('name', '=like', f"{account.display_name}%%"),
        ])
        return account.display_name if not copied_count else f"{account.display_name} ({copied_count})"

    def _create_reconciliation_rule(self, rule_data):
        """Creates and returns a  new reconciliation rule based on prepared data."""
        vals = {
            'created_automatically': True,
            'name': rule_data['name'],
            'match_journal_ids': self.journal_id.ids,
            'match_label': 'match_regex',
            'match_label_param': rule_data['common_substring'],
            'line_ids': [
                Command.create({
                    'account_id': rule_data['account'].id,
                    'amount_type': 'percentage',
                    'amount_string': '100',
                    'label': rule_data['account'].name,
                }),
            ],
        }

        if rule_data['partner_ids']:
            vals['match_partner_ids'] = rule_data['partner_ids']

        return self.with_user(SUPERUSER_ID).with_company(self.journal_id.company_id).env['account.reconcile.model'].create(vals)

    def _get_common_substring(self, labels):
        """
        Returns the normalised longest common substring that is at least 10 characters long from a list
        of labels. For shorter substrings, returns the normalised label if all labels are identical after
        normalisation, otherwise returns None.

        :param labels: List of string labels to process
        :return: Longest common substring if 10+ chars, normalised label if all identical post-normalisation, otherwise None
        """
        def normalise_label(label):
            """
                This method will escape the special characters and the digits (if and only if) the label is a
                structured reference.
            """
            is_valid = is_valid_structured_reference(label)
            label = re.escape(label)
            if not is_valid:
                label = re.sub(r'\d+', r'\\d+', label)
            return label

        def get_all_substrings(label):
            """
                Generate all possible substrings of a given string.
                Example:
                    get_all_substrings("abc")
                    {'a', 'b', 'c', 'ab', 'bc', 'abc'}
                :param label: string that has been normalised
                :return: A set containing all unique substrings of the input string.
            """
            return {
                label[i:j]
                for i in range(len(label))
                for j in range(i + 1, len(label) + 1)
            }

        normalised = [normalise_label(label.upper()) for label in labels if label]
        # If they're all the same after normalising, then we don't care about the size being 10 chars or more.
        if all(label == normalised[0] for label in normalised[1:]):
            return normalised[0]
        # Sorting by length, so we start with the shortest strings first. This will allow us to exit early
        # if the size of the substring drops under 10.
        normalised.sort(key=len)

        # To achieve this:
        # 1. Use `get_all_substrings` on each normalized label to get all possible substrings.
        # 2. Perform a set intersection on the resulting sets to find substrings common to all labels.
        # 3. From the common substrings, select the longest one using `max` with `key=len`.
        # 4. If no common substring exists, return an empty string as the default.
        substring = max(set.intersection(*map(get_all_substrings, normalised)), key=len, default="")

        return substring if len(substring) >= 10 else None

    def _create_account_model_fee(self, account_id):
        """
            In case of a statement line nearly matching an invoice (entering money on the statement line),
            when a user puts the leftover on an account,
            create a new model for these type of fees with the account if it does not exist already
        """
        def create_reco_model_xml_id(name, journal):
            self.env['account.reconcile.model']._load_records([{
                'xml_id': f'account.account_reco_model_fee_{journal.id}',
                'values': {
                    'company_id': journal.company_id.id,
                    'match_journal_ids': journal.ids,
                    'name': name,
                    'line_ids': [Command.create({
                        'account_id': account_id,
                        'label': _('Bank Fees'),
                        'amount_type': 'percentage',
                        'amount_string': '100',
                    })]
                },
            }])
        if (
            self.currency_id.compare_amounts(self.amount, 0) < 0
            or self.currency_id.compare_amounts(self.amount_residual, 0) < 0
            or self.currency_id.compare_amounts(abs(self.amount_residual), 0.03 * (self.amount_currency if self.foreign_currency_id else self.amount)) > 0
        ):
            return

        journal = self.journal_id
        if self.env.ref(f'account.account_reco_model_fee_{journal.id}', raise_if_not_found=False):
            return

        base_model_name = f'Fees ({journal.name})'
        existing_journal_names = set(
            self.env['account.reconcile.model'].search_fetch(
                [
                    ('name', 'like', base_model_name + '%'),
                    *self.env['account.journal']._check_company_domain(journal.company_id)
                ],
                ['name'],
            ).mapped('name')
        )
        if base_model_name not in existing_journal_names:
            create_reco_model_xml_id(base_model_name, journal)
        else:
            for num in range(2, 100):
                new_model_name = f'{base_model_name} {num}'
                if new_model_name not in existing_journal_names:
                    create_reco_model_xml_id(new_model_name, journal)
                    return

            # If we could not find a valid code due to multiple journals with the same name,
            # do it with the journal name and the journal code (which is unique)
            create_reco_model_xml_id(f'Fees ({journal.name} - {journal.code})', journal)

    def set_line_bank_statement_line(self, move_lines_ids):
        """ Sets the specified move lines to the bank statement line and performs reconciliation.

            :param move_lines_ids: A list of IDs for the move lines to be added to the bank statement line.
        """
        self.ensure_one()
        # We do not want to set a line that is already reconciled, otherwise a user error would be raised. The order
        # is there to keep the same order as the one received in move_line_ids
        move_lines = self.env['account.move.line'].search([
            ('id', 'in', move_lines_ids),
            ('reconciled', '=', False),
        ], order="sequence DESC")
        if not move_lines:
            return

        _liquidity_line, _suspense_lines, other_lines = self._seek_for_lines()

        transaction_amount, transaction_currency, journal_amount, journal_currency, company_amount, company_currency = self._get_accounting_amounts_and_currencies()
        journal_transaction_rate = abs(transaction_amount / journal_amount) if journal_amount else 0.0
        company_transaction_rate = abs(transaction_amount / company_amount) if company_amount else 0.0

        open_balance = company_amount
        open_amount_currency = transaction_amount
        total_early_payment_discount = 0.0
        early_pay_aml_values_list = []

        for line in other_lines + move_lines:
            # move_lines are the lines coming from the reconcile button and other_lines are the lines from the bank
            # statement move (so they are reconciled). We need to invert the sign of move_lines since a positive
            # move_line need to be put as negative in the bank statement move.
            # For the other lines, we can use the balance and amount currency since they are the line on the bank move
            if line in move_lines:
                sign = -1
                amount = line.amount_residual
                amount_currency = line.amount_residual_currency
            else:
                sign = 1
                amount = line.balance
                amount_currency = line.amount_currency

            # Early payment Discount
            if line.move_id._is_eligible_for_early_payment_discount(transaction_currency, self.date):
                total_early_payment_discount += line.amount_currency - line.discount_amount_currency
                early_pay_aml_values_list.append({
                    'aml': line,
                    'amount_currency': -line.amount_currency,
                    'balance': -amount,
                })

            exchange_diff_balance = self._lines_get_account_balance_exchange_diff(line.currency_id, amount, amount_currency)
            line_balance = amount + exchange_diff_balance
            open_balance += (line_balance * sign)

            if line.currency_id == transaction_currency:
                open_amount_currency += amount_currency * sign
            elif line.currency_id == journal_currency:
                open_amount_currency += transaction_currency.round(amount_currency * journal_transaction_rate) * sign
            else:
                open_amount_currency += transaction_currency.round(line_balance * company_transaction_rate) * sign

        new_lines = []
        is_early_payment_discount = False
        has_exchange_diff = False
        residual_amount = company_amount + sum(line.balance for line in other_lines)
        for index, move_line in enumerate(move_lines):
            exchange_diff_balance = self._lines_get_account_balance_exchange_diff(move_line.currency_id, move_line.amount_residual, move_line.amount_residual_currency)
            has_exchange_diff = not move_line.currency_id.is_zero(exchange_diff_balance)
            current_balance = -(move_line.amount_residual + exchange_diff_balance)
            residual_amount += current_balance

            new_line_balance = current_balance
            new_amount_currency = -move_line.amount_residual_currency

            # Partial amount will be calculated only on the last invoice of the one selected by the user.
            if index == len(move_lines) - 1:
                partial_amounts = (
                    self._get_partial_amounts(current_balance, move_line, open_amount_currency, open_balance)
                    if (company_currency.compare_amounts(residual_amount, 0) < 0 if company_currency.compare_amounts(company_amount, 0) > 0 else company_currency.compare_amounts(residual_amount, 0) > 0)
                    else None
                )
                if partial_amounts and not company_currency.is_zero(partial_amounts['partial_balance']):
                    new_line_balance = partial_amounts['partial_balance']
                    new_amount_currency = partial_amounts['partial_amount_currency']

            if is_early_payment_discount := move_line.move_id._is_eligible_for_early_payment_discount(transaction_currency, self.date):
                new_line_balance = -move_line.amount_residual
                new_amount_currency = -move_line.amount_residual_currency

            new_lines.append(move_line._get_aml_values(
                balance=new_line_balance,
                amount_currency=new_amount_currency,
                currency_id=move_line.currency_id.id,
                reconciled_lines_ids=[Command.set(move_line.ids)],
            ))
            self.move_id._compute_checked()  # to add to compute dependencies

        if is_early_payment_discount and open_amount_currency and self._qualifies_for_early_payment(transaction_currency, open_amount_currency, total_early_payment_discount):
            new_lines.extend(self._set_early_payment_discount_lines(early_pay_aml_values_list, open_balance))

        self.with_context(no_exchange_difference_no_recursive=not has_exchange_diff)._add_move_line_to_statement_line_move(new_lines)

    def _get_partial_amounts(self, current_balance, move_line, open_amount_currency, open_balance):
        def has_enough(currency, open_amount, current_amount):
            return (
                currency.compare_amounts(open_amount, 0) > 0
                and currency.compare_amounts(current_amount, 0) > 0
                and currency.compare_amounts(current_amount, open_amount) > 0
            )
        transaction_amount, transaction_currency, _journal_amount, _journal_currency, company_amount, company_currency = self._get_accounting_amounts_and_currencies()
        has_enough_comp_debit = has_enough(company_currency, open_balance, current_balance)
        has_enough_comp_credit = has_enough(company_currency, -open_balance, -current_balance)
        current_amount_currency = -move_line.amount_residual_currency
        has_enough_curr_debit = has_enough(move_line.currency_id, open_amount_currency, current_amount_currency)
        has_enough_curr_credit = has_enough(move_line.currency_id, -open_amount_currency, -current_amount_currency)

        if move_line.currency_id == transaction_currency and (has_enough_curr_debit or has_enough_curr_credit):
            new_amount_currency = (
                current_amount_currency
                # If the open amount is small, fully reconcile the move_line and not the transaction
                if move_line.currency_id.compare_amounts(abs(open_amount_currency), 0.03 * abs(current_amount_currency)) < 0
                else current_amount_currency - open_amount_currency
            )
            rate = abs(company_amount / transaction_amount) if transaction_amount else 0.0

            # Compute the amounts to make a partial.
            balance_after_partial = move_line.company_currency_id.round(new_amount_currency * rate)
            return {
                'partial_balance': balance_after_partial,
                'partial_amount_currency': new_amount_currency,
            }
        elif has_enough_comp_debit or has_enough_comp_credit:
            # Compute the new value for balance.
            balance_after_partial = (
                current_balance
                # If the open amount is small, fully reconcile the move_line and not the transaction
                if move_line.currency_id.compare_amounts(abs(open_balance), 0.03 * abs(current_balance)) < 0
                else current_balance - open_balance
            )
            # Get the rate of the original journal item.
            rate = move_line.currency_rate

            # Compute the amounts to make a partial.
            new_line_balance = move_line.company_currency_id.round(balance_after_partial * abs(move_line.amount_residual) / abs(current_balance))
            new_amount_currency = move_line.currency_id.round(new_line_balance * rate)

            # Some amounts might have just lost their precision due to all the rounding operations.
            # Assume they're the same if its raw conversion is close enough.
            if company_currency.compare_amounts(new_line_balance, (-move_line.amount_residual_currency / rate)) == 0:
                new_amount_currency = -move_line.amount_residual_currency

            return {
                'partial_balance': balance_after_partial,
                'partial_amount_currency': new_amount_currency,
            }
        return None

    def _lines_get_account_balance_exchange_diff(self, currency_id, amount, amount_currency):
        # Compute the balance of the line using the rate/currency coming from the bank transaction.
        amounts_in_st_curr = self._prepare_counterpart_amounts_using_st_line_rate(
            currency_id,
            amount,
            amount_currency,
        )
        transaction_currency_id = self.foreign_currency_id or self.currency_id
        origin_balance = amounts_in_st_curr['balance']
        if currency_id == self.company_currency_id and transaction_currency_id != self.company_currency_id:
            # The reconciliation will be expressed using the rate of the statement line.
            origin_balance = amount
        elif currency_id != self.company_currency_id and transaction_currency_id == self.company_currency_id:
            # The reconciliation will be expressed using the foreign currency of the aml to cover the Mexican case.
            origin_balance = currency_id._convert(amount_currency, transaction_currency_id, self.company_id, self.date)

        # Compute the exchange difference balance.
        # Useful for example when the currency has a rounding of 1 and that we have a exchange diff of 0.01, we don't want
        # the exchange diff to be created.
        if currency_id.is_zero(origin_balance - amount):
            return 0.0

        return self.company_currency_id.round(origin_balance - amount)

    @api.model
    def _qualifies_for_early_payment(self, transaction_currency, open_amount_currency, total_early_payment_discount):
        return transaction_currency.is_zero(open_amount_currency + total_early_payment_discount)

    def _set_early_payment_discount_lines(self, early_pay_aml_values_list, open_balance):
        early_payment_values = self.env['account.move']._get_invoice_counterpart_amls_for_early_payment_discount(
            early_pay_aml_values_list,
            -open_balance,
        )
        new_lines = []

        for vals_list in early_payment_values.values():
            for vals in vals_list:
                new_lines.append({
                    'account_id': vals['account_id'],
                    'date': self.date,
                    'name': vals['name'],
                    'partner_id': vals['partner_id'],
                    'currency_id': vals['currency_id'],
                    'amount_currency': vals['amount_currency'],
                    'balance': vals['balance'],
                    'analytic_distribution': vals.get('analytic_distribution'),
                    'tax_ids': vals.get('tax_ids', []),
                    'tax_tag_ids': vals.get('tax_tag_ids', []),
                    'tax_repartition_line_id': vals.get('tax_repartition_line_id'),
                    'group_tax_id': vals.get('group_tax_id'),
                })
        return new_lines

    def delete_reconciled_line(self, move_line_ids):
        """ Deletes the specified move lines from the bank statement line after unreconciling them.

            :param move_line_ids: A list of move line IDs to be deleted.
        """
        self.ensure_one()
        if self.checked and self.is_reconciled and not self.move_id._is_user_able_to_review():
            raise ValidationError(_("Validated entries can only be changed by your accountant."))

        move_lines_to_remove = self.env['account.move.line'].browse(move_line_ids)
        liquidity_line, _suspense_lines, other_lines = self._seek_for_lines()
        reco_model_id = move_lines_to_remove.reconcile_model_id[:1]

        move_lines_to_remove.remove_move_reconcile()
        self._set_move_line_to_statement_line_move(
            liquidity_line + other_lines - move_lines_to_remove,
            [],
        )
        if reco_model_id:
            self._action_manual_reco_model(reco_model_id)

    def edit_reconcile_line(self, move_line_id, record_data):
        """ Edits the specified move line from the bank statement line with the given data.
            We can only edit line that are not linked to a move line.

            :param move_line_id: The ID of the move line to be edited.
            :param record_data: A dictionary containing the data to update the move line with.
        """
        self.ensure_one()
        if self.checked and self.is_reconciled and not self.move_id._is_user_able_to_review():
            raise ValidationError(_("Validated entries can only be changed by your accountant."))

        move_line_to_edit = self.env['account.move.line'].browse(move_line_id)
        liquidity_lines, _suspense_lines, other_lines = self._seek_for_lines()

        edited_move_reconciled_line_ids = move_line_to_edit.reconciled_lines_ids.ids
        move_line_to_edit.remove_move_reconcile()
        move_line_to_edit_vals = move_line_to_edit._get_aml_values(**record_data)
        if edited_move_reconciled_line_ids:
            move_line_to_edit_vals['reconciled_lines_ids'] = [Command.set(edited_move_reconciled_line_ids)]

        self._set_move_line_to_statement_line_move(
            (liquidity_lines + other_lines) - move_line_to_edit,
            [move_line_to_edit_vals],
        )

        if record_data.get('tax_ids'):
            self._recompute_tax_lines()

        edited_line = self.line_ids - (liquidity_lines + other_lines)
        # Means that we tried to remove the partner
        if 'partner_id' in record_data and not record_data['partner_id']:
            edited_line.partner_id = False

    def _recompute_tax_lines(self):
        self.ensure_one()
        liquidity_lines, _suspense_lines, other_lines = self._seek_for_lines()
        other_lines.filtered(lambda line: not line.reconciled_lines_ids)  # We do not recompute tax on lines that come from invoice

        AccountTax = self.env['account.tax']
        base_amls = other_lines.filtered(lambda line: not line.tax_repartition_line_id)
        base_lines = [self._prepare_base_line_for_taxes_computation(line) for line in base_amls]
        tax_amls = other_lines - base_amls
        tax_lines = [self._prepare_tax_line_for_taxes_computation(line) for line in tax_amls]
        AccountTax._add_tax_details_in_base_lines(base_lines, self.company_id)
        AccountTax._round_base_lines_tax_details(base_lines, self.company_id)
        AccountTax._add_accounting_data_in_base_lines_tax_details(base_lines, self.company_id, include_caba_tags=True)
        tax_results = AccountTax._prepare_tax_lines(base_lines, self.company_id, tax_lines=tax_lines)

        lines_to_delete = self.env['account.move.line']
        lines_to_add_or_update = []

        # Update the base lines.
        for base_line, to_update in tax_results['base_lines_to_update']:
            line = base_line['record']
            amount_currency = to_update['amount_currency']
            balance = self._prepare_counterpart_amounts_using_st_line_rate(line.currency_id, line.amount_residual, amount_currency)['balance']
            lines_to_delete += line
            lines_to_add_or_update.append(line._get_aml_values(balance=balance, amount_currency=amount_currency, tax_tag_ids=to_update['tax_tag_ids']))

        # Tax lines that are no longer needed.
        for tax_line_vals in tax_results['tax_lines_to_delete']:
            lines_to_delete += tax_line_vals['record']

        # Newly created tax lines.
        for tax_line_vals in tax_results['tax_lines_to_add']:
            lines_to_add_or_update.append(self._lines_prepare_tax_line(tax_line_vals))

        # Update of existing tax lines.
        for tax_line_vals, grouping_key, to_update in tax_results['tax_lines_to_update']:
            lines_to_delete += tax_line_vals['record']
            new_line_vals = self._lines_prepare_tax_line({**grouping_key, **to_update})
            lines_to_add_or_update.append(tax_line_vals['record']._get_aml_values(**new_line_vals))

        lines_to_keep = (liquidity_lines + other_lines) - lines_to_delete
        self._set_move_line_to_statement_line_move(lines_to_keep, lines_to_add_or_update)

    def _lines_prepare_tax_line(self, tax_line_vals):
        self.ensure_one()

        tax_rep = self.env['account.tax.repartition.line'].browse(tax_line_vals['tax_repartition_line_id'])
        name = tax_rep.tax_id.name
        if self.payment_ref:
            name = f'{name} - {self.payment_ref}'
        currency = self.env['res.currency'].browse(tax_line_vals['currency_id'])
        amount_currency = tax_line_vals['amount_currency']
        balance = self._prepare_counterpart_amounts_using_st_line_rate(currency, None, amount_currency)['balance']

        return {
            'account_id': tax_line_vals['account_id'],
            'date': self.date,
            'name': name,
            'partner_id': tax_line_vals['partner_id'],
            'currency_id': currency.id,
            'amount_currency': amount_currency,
            'balance': balance,
            'analytic_distribution': tax_line_vals['analytic_distribution'],
            'tax_repartition_line_id': tax_rep.id,
            'tax_ids': tax_line_vals['tax_ids'],
            'tax_tag_ids': tax_line_vals['tax_tag_ids'],
            'group_tax_id': tax_line_vals['group_tax_id'],
        }

    def _prepare_base_line_for_taxes_computation(self, line_vals):
        """ Convert the current dictionary to use the generic taxes computation method defined on account.tax.

            :returns: A dictionary representing a base line.
        """
        self.ensure_one()
        if not line_vals:
            return {}

        tax_type = line_vals.tax_ids[0].type_tax_use if line_vals.tax_ids else None
        is_refund = (tax_type == 'sale' and line_vals.balance > 0.0) or (tax_type == 'purchase' and line_vals.balance < 0.0)

        return self.env['account.tax']._prepare_base_line_for_taxes_computation(
            line_vals,
            price_unit=line_vals.amount_currency,
            quantity=1.0,
            is_refund=is_refund,
            special_mode='total_included',
        )

    def _prepare_tax_line_for_taxes_computation(self, line):
        """ Convert the current dictionary to use the generic taxes computation method defined on account.tax.

            :return: A dictionary representing a tax line.
        """
        self.ensure_one()
        if not line:
            return {}
        return self.env['account.tax']._prepare_tax_line_for_taxes_computation(line)

    def _reconcile_payments(self, payments, amls_to_create, reconciled_lines=None):
        self.ensure_one()
        has_exchange_diff = False
        if reconciled_lines:
            for reconciled_line, aml_to_create in zip(reconciled_lines, amls_to_create):
                exchange_diff_balance = self._lines_get_account_balance_exchange_diff(reconciled_line.currency_id, reconciled_line.amount_residual, reconciled_line.amount_residual_currency)
                has_exchange_diff = has_exchange_diff or not reconciled_line.currency_id.is_zero(exchange_diff_balance)
                new_balance = -(reconciled_line.amount_residual + exchange_diff_balance)

                aml_to_create['balance'] = new_balance

        self.with_context(no_exchange_difference_no_recursive=not has_exchange_diff)._add_move_line_to_statement_line_move(amls_to_create)
        if payments_to_validate := payments.filtered(lambda p: not p.move_id and p.state in self.env['account.batch.payment']._valid_payment_states()):
            payments_to_validate.action_validate()

    def create_document_from_attachment(self, attachment_ids):
        """ Create the invoices from files.
            :return: A action redirecting to account.move list/form view.
        """
        statement_line = self.browse(self.env.context.get("statement_line_id"))

        purchase_journal_id = self.env['account.journal'].search_fetch(
            domain=[*self.env['account.journal']._check_company_domain(statement_line.company_id), ('type', '=', 'purchase')],
            field_names=['id'],
            limit=1,
        )
        invoices = purchase_journal_id.with_context(default_move_type="in_invoice")._create_document_from_attachment(attachment_ids)
        return invoices._get_records_action()

    def action_unreconcile_entry(self):
        self.ensure_one()

        _liquidity_lines, _suspense_lines, other_lines = self._seek_for_lines()
        other_lines.remove_move_reconcile()

    @api.model_create_multi
    def create(self, vals_list):
        statement_lines = super().create(vals_list)
        if not self.env.context.get('no_retrieve_partner'):
            statement_lines._retrieve_partner()
        for statement_line in statement_lines:
            if statement_line.transaction_details:
                statement_line.move_id.message_post(body=statement_line._format_transaction_details())

        # process automatically the new lines in case we pass some context key (i.e coming from the bank reconciliation widget)
        if self.env.context.get('auto_statement_processing', False) and statement_lines:
            statement_lines._try_auto_reconcile_statement_lines()
        return statement_lines

    def _format_transaction_details(self):
        """ Format the 'transaction_details' field of the statement line to be more readable for the end user.

        Example:
            {
                "debtor": {
                    "name": None,
                    "private_id": None,
                },
                "debtor_account": {
                    "iban": "BE84103080286059",
                    "bank_transaction_code": None,
                    "credit_debit_indicator": "DBIT",
                    "status": "BOOK",
                    "value_date": "2022-12-29",
                    "transaction_date": None,
                    "balance_after_transaction": None,
                },
            }

        Becomes:
            debtor_account:
                iban: BE84103080286059
                credit_debit_indicator: DBIT
                status: BOOK
                value_date: 2022-12-29

        :returns: An html representation of the transaction details.
        """
        self.ensure_one()
        details = self.transaction_details
        if not details:
            return

        def _get_formatted_data(data, prefix=""):
            keys = data.keys() if isinstance(data, dict) else [i for i, _ in enumerate(data)]
            result = Markup()
            for key in keys:
                value = data[key]
                result += prefix + Markup("<b>%s:</b> ") % str(key)
                if isinstance(value, (list, dict)):
                    result += "\n"
                    result += _get_formatted_data(value, prefix + "  ")
                    continue
                result += str(value) + "\n"
            return result

        res = _get_formatted_data(details)
        return Markup("<div><pre>%s</pre></div>") % res
