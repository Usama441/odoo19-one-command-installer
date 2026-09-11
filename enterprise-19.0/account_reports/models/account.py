# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.
import json

from dateutil.relativedelta import relativedelta

from odoo import api, fields, models
from odoo.tools import SQL, OrderedSet, html2plaintext
from odoo.addons.account_reports.models.account_audit_account_status import STATUS_SELECTION


class AccountAccount(models.Model):
    _inherit = "account.account"

    exclude_provision_currency_ids = fields.Many2many('res.currency', relation='account_account_exclude_res_currency_provision', help="Whether or not we have to make provisions for the selected foreign currencies.")
    budget_item_ids = fields.One2many(comodel_name='account.report.budget.item', inverse_name='account_id')  # To use it in the domain when adding accounts from the report

    audit_debit = fields.Monetary(string="Debit", compute="_compute_audit_period", currency_field="company_currency_id", search="_search_audit_debit")
    audit_credit = fields.Monetary(string="Credit", compute="_compute_audit_period", currency_field="company_currency_id", search="_search_audit_credit")
    audit_balance = fields.Monetary(string="Balance", compute="_compute_audit_period", currency_field="company_currency_id", search="_search_audit_balance")
    audit_balance_show_warning = fields.Boolean(compute="_compute_audit_balance_show_warning")
    audit_previous_balance = fields.Monetary(string="Balance N-1", compute="_compute_audit_period", currency_field="company_currency_id", search="_search_audit_previous_balance")
    audit_previous_balance_show_warning = fields.Boolean(compute="_compute_audit_previous_balance_show_warning")
    audit_var_n_1 = fields.Monetary(string="Var N-1", compute="_compute_audit_variation", currency_field="company_currency_id", search="_search_audit_var_n_1")
    audit_var_percentage = fields.Float(string="Var %", compute="_compute_audit_variation", search="_search_var_percentage", default=False)
    audit_status = fields.Selection(selection=STATUS_SELECTION, string="Status", compute="_compute_audit_status", inverse="_inverse_audit_status")

    account_status = fields.One2many(string="Account Status", comodel_name='account.audit.account.status', inverse_name='account_id')
    last_message = fields.Char(string="Last Message", compute='_compute_last_message')

    def _common_audit_search(self, field_name, operator, value, previous=False):
        if isinstance(value, OrderedSet):
            value = tuple(value)

        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))
        if not working_file:
            return []

        date_to = working_file.date_to
        if previous:
            date_to = working_file.type_id._get_period_boundaries(working_file.company_id, working_file.date_from - relativedelta(days=1))[1]

        self.env.cr.execute(
            SQL("""
                SELECT
                    aml.account_id
                FROM (
                    SELECT
                        SUM(COALESCE(account_move_line.%(field_name)s)) as %(field_name)s,
                        %(account_or_unaff)s AS account_id
                    FROM account_move_line
                    JOIN account_account aml_account ON aml_account.id = account_move_line.account_id
                    WHERE account_move_line.date <= %(date_to)s
                      AND account_move_line.company_id = ANY(%(company_ids)s)
                      AND account_move_line.parent_state = 'posted'
                    GROUP BY %(account_or_unaff)s
                ) aml
                WHERE aml.%(field_name)s %(operator)s %(value)s
                """,
                field_name=SQL(field_name),
                account_or_unaff=self._get_account_or_unaff_id_sql_redirection(working_file, working_file.date_from, "account_move_line", "aml_account"),
                date_to=date_to,
                company_ids=working_file.company_ids.ids,
                operator=SQL(operator),
                value=value,
            )
        )

        result = self.env.cr.dictfetchall()
        return [('id', 'in', [row['account_id'] for row in result])]

    def _search_audit_debit(self, operator, value):
        return self._common_audit_search('debit', operator, value)

    def _search_audit_credit(self, operator, value):
        return self._common_audit_search('credit', operator, value)

    def _search_audit_balance(self, operator, value):
        return self._common_audit_search('balance', operator, value)

    def _search_audit_previous_balance(self, operator, value):
        return self._common_audit_search('balance', operator, value, True)

    def _search_variation_common(self, variation_select, operator, value):
        if isinstance(value, OrderedSet):
            value = tuple(value)

        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))
        if not working_file:
            return []

        prev_date_from, prev_date_to = working_file.type_id._get_period_boundaries(working_file.company_id, working_file.date_from - relativedelta(days=1))

        self.env.cr.execute(
            SQL("""
                SELECT
                    account_variation.account_id
                FROM (

                    SELECT
                        %(variation_select)s,
                        %(account_or_unaff)s AS account_id
                    FROM account_move_line aml
                    JOIN account_account aml_account ON aml_account.id = aml.account_id

                    LEFT JOIN (
                        SELECT
                            SUM(COALESCE(prev_aml.balance)) as balance,
                            %(prev_account_or_unaff)s AS account_id
                        FROM account_move_line prev_aml
                        JOIN account_account prev_aml_account ON prev_aml_account.id = prev_aml.account_id
                        WHERE prev_aml.date <= %(prev_date_to)s
                          AND prev_aml.company_id = ANY(%(company_ids)s)
                        GROUP BY %(prev_account_or_unaff)s
                    ) prev_account_balances ON %(account_or_unaff)s = prev_account_balances.account_id

                    WHERE aml.date <= %(date_to)s AND aml.company_id = ANY(%(company_ids)s)
                    GROUP BY %(account_or_unaff)s, prev_account_balances.balance

                ) account_variation
                WHERE account_variation.variation %(operator)s %(value)s
                """,
                variation_select=variation_select,
                date_from=working_file.date_from,
                date_to=working_file.date_to,
                prev_date_from=prev_date_from,
                prev_date_to=prev_date_to,
                prev_account_or_unaff=self._get_account_or_unaff_id_sql_redirection(working_file, prev_date_from, "prev_aml", "prev_aml_account"),
                account_or_unaff=self._get_account_or_unaff_id_sql_redirection(working_file, working_file.date_from, "aml", "aml_account"),
                company_ids=working_file.company_ids.ids,
                operator=SQL(operator),
                value=value,
            )
        )

        result = self.env.cr.dictfetchall()
        return [('id', 'in', [row['account_id'] for row in result])]

    def _search_audit_var_n_1(self, operator, value):
        return self._search_variation_common(SQL("(COALESCE(SUM(aml.balance), 0.0) - COALESCE(prev_account_balances.balance, 0)) as variation"), operator, value)

    def _search_var_percentage(self, operator, value):
        return self._search_variation_common(
            SQL("""
                CASE WHEN prev_account_balances.balance IS NULL THEN NULL
                ELSE (COALESCE(SUM(aml.balance), 0) - COALESCE(prev_account_balances.balance, 0)) / COALESCE(prev_account_balances.balance, 1) * 100
                END as variation
            """),
            operator, value)

    @api.depends_context('working_file_id')
    def _compute_audit_period(self):
        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))
        balances_by_account = {}

        if working_file:
            prev_date_from, prev_date_to = working_file.type_id._get_period_boundaries(working_file.company_id, working_file.date_from - relativedelta(days=1))
            audit_period_query = SQL("""
                    SELECT
                        COALESCE(SUM(aml.debit), 0) AS current_debit,
                        COALESCE(SUM(aml.credit), 0) AS current_credit,
                        COALESCE(SUM(aml.balance), 0) AS current_balance,
                        prev_account_balances.balance AS prev_balance,
                        %(account_or_unaff)s AS account_id
                    FROM account_move_line aml
                    JOIN account_account aml_account ON aml_account.id = aml.account_id
                    LEFT JOIN (
                        SELECT
                            SUM(COALESCE(prev_aml.balance, 0)) as balance,
                            %(prev_account_or_unaff)s AS account_id
                        FROM account_move_line prev_aml
                        JOIN account_account prev_aml_account ON prev_aml_account.id = prev_aml.account_id
                        WHERE prev_aml.date <= %(prev_date_to)s
                        AND prev_aml.company_id = ANY(%(company_ids)s)
                        GROUP BY %(prev_account_or_unaff)s
                    ) prev_account_balances ON %(account_or_unaff)s = prev_account_balances.account_id

                    WHERE aml.date <= %(date_to)s AND aml.company_id = ANY(%(company_ids)s)
                    GROUP BY %(account_or_unaff)s, prev_account_balances.balance
                """,
                date_from=working_file.date_from,
                date_to=working_file.date_to,
                prev_date_from=prev_date_from,
                prev_date_to=prev_date_to,
                prev_account_or_unaff=self._get_account_or_unaff_id_sql_redirection(working_file, prev_date_from, "prev_aml", "prev_aml_account"),
                account_or_unaff=self._get_account_or_unaff_id_sql_redirection(working_file, working_file.date_from, "aml", "aml_account"),
                company_ids=working_file.company_ids.ids,
            )
            self.env.cr.execute(audit_period_query)

            balances_by_account = {
                row['account_id']: (
                    row['current_debit'],
                    row['current_credit'],
                    row['current_balance'],
                    row['prev_balance'],
                )
                for row in self.env.cr.dictfetchall()
            }

        for account in self:
            debit, credit, balance, prev_balance = balances_by_account.get(account.id, (0, 0, 0, 0))
            account.audit_debit = debit
            account.audit_credit = credit
            account.audit_balance = balance
            account.audit_previous_balance = prev_balance

    @api.depends('audit_balance', 'audit_previous_balance')
    def _compute_audit_variation(self):
        for account in self:
            account.audit_var_n_1 = account.audit_balance - account.audit_previous_balance

            if self.env.company.currency_id.is_zero(account.audit_previous_balance):
                account.audit_var_percentage = False
            else:
                account.audit_var_percentage = (account.audit_balance - account.audit_previous_balance) / account.audit_previous_balance

    @api.depends_context('working_file_id')
    def _compute_audit_status(self):
        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))

        self.audit_status = 'todo'

        if working_file:
            create_vals = []
            account_status_by_account = {status.account_id: status for status in working_file.audit_account_status_ids}
            for account in self:
                if account in account_status_by_account:
                    account.audit_status = account_status_by_account[account].status
                else:
                    create_vals.append({
                        'account_id': account.id,
                        'audit_id': working_file.id,
                    })
            if create_vals:
                self.env['account.audit.account.status'].create(create_vals)

    def _inverse_audit_status(self):
        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))

        if working_file:
            account_status_by_account = {status.account_id: status for status in working_file.audit_account_status_ids}
            for account in self:
                if account in account_status_by_account:
                    account_status_by_account[account].status = account.audit_status

    def _compute_balance_warning(self, balance_field_name, warning_field_name):
        for account in self:
            if account.internal_group == 'asset':
                account[warning_field_name] = account.company_currency_id.compare_amounts(account[balance_field_name], 0) == -1
            elif account.internal_group == 'liability':
                account[warning_field_name] = account.company_currency_id.compare_amounts(account[balance_field_name], 0) == 1
            else:
                account[warning_field_name] = False

    @api.depends('audit_balance')
    def _compute_audit_balance_show_warning(self):
        self._compute_balance_warning('audit_balance', 'audit_balance_show_warning')

    @api.depends('audit_previous_balance')
    def _compute_audit_previous_balance_show_warning(self):
        self._compute_balance_warning('audit_previous_balance', 'audit_previous_balance_show_warning')

    @api.depends_context('working_file_id')
    def _compute_last_message(self):
        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))
        if not working_file:
            for account in self:
                account.last_message = False
            return

        self.env['mail.message'].flush_model(['model', 'res_id', 'body'])
        self.env['account.report.annotation'].flush_model(['message_id'])

        self.env.cr.execute("""
            SELECT DISTINCT ON (message.res_id) message.res_id, message.body
            FROM mail_message message
            JOIN account_report_annotation annotation ON annotation.message_id = message.id
            WHERE message.model = 'account.account' AND message.res_id = ANY(%s)
            ORDER BY message.res_id, message.create_date DESC
        """, (self.ids,))
        last_message_by_account = {
            row[0]: html2plaintext(row[1])
            for row in self.env.cr.fetchall()
        }

        for account in self:
            account.last_message = last_message_by_account.get(account.id, False)

    def _field_to_sql(self, alias, field_expr, query=None) -> SQL:
        def add_aml_join(join_alias, date_from, date_to, company_ids):
            query.add_join(
                'LEFT JOIN',
                join_alias,
                SQL("""
                    (SELECT
                        SUM(COALESCE(aml.debit, 0.0)) as debit,
                        SUM(COALESCE(aml.credit, 0.0)) as credit,
                        SUM(COALESCE(aml.balance, 0.0)) as balance,
                        %(account_or_unaff)s as account_id
                    FROM account_move_line aml
                    JOIN account_account aml_account ON aml_account.id = aml.account_id
                    WHERE aml.date <= %(date_to)s
                      AND aml.company_id = ANY(%(company_ids)s)
                      AND aml.parent_state = 'posted'
                    GROUP BY %(account_or_unaff)s)
                    """,
                    account_or_unaff=self._get_account_or_unaff_id_sql_redirection(working_file, working_file.date_from, "aml", "aml_account"),
                    date_to=date_to,
                    company_ids=company_ids
                ),

                SQL("%s = %s", SQL.identifier(join_alias, 'account_id'), self._field_to_sql(alias, 'id', query))
            )

        if field_expr not in ('audit_debit', 'audit_credit', 'audit_balance', 'audit_previous_balance', 'audit_status', 'audit_var_n_1', 'audit_var_percentage'):
            return super()._field_to_sql(alias, field_expr, query)

        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))
        if not working_file:
            return SQL()

        if field_expr in ('audit_debit', 'audit_credit', 'audit_balance'):
            field_name = field_expr.replace('audit_', '')
            add_aml_join('current_account_move_lines', working_file.date_from, working_file.date_to, working_file.company_ids.ids)
            return SQL("COALESCE(%s, 0.0)", SQL.identifier('current_account_move_lines', field_name))

        if field_expr == 'audit_previous_balance':
            previous_period_start, previous_period_end = working_file.type_id._get_period_boundaries(working_file.company_id, (working_file.date_from or fields.Date.today()) - relativedelta(days=1))
            add_aml_join('prev_account_move_line', previous_period_start, previous_period_end, working_file.company_ids.ids)
            return SQL("COALESCE(prev_account_move_line.balance, 0.0)")

        if field_expr == 'audit_status':
            query.add_join(
                'LEFT JOIN',
                'account_audit_account_status',
                'account_audit_account_status',
                SQL("account_audit_account_status.audit_id = %s AND account_audit_account_status.account_id = %s", self.env.context.get('working_file_id'), self._field_to_sql(alias, 'id', query))
            )
            return SQL('account_audit_account_status.status')

        if field_expr in ('audit_var_n_1', 'audit_var_percentage'):
            previous_period_start, previous_period_end = working_file.type_id._get_period_boundaries(working_file.company_id, (working_file.date_from or fields.Date.today()) - relativedelta(days=1))
            add_aml_join('current_account_move_lines', working_file.date_from, working_file.date_to, working_file.company_ids.ids)
            add_aml_join('prev_account_move_line', previous_period_start, previous_period_end, working_file.company_ids.ids)
            if field_expr == 'audit_var_n_1':
                return SQL("(COALESCE(current_account_move_lines.balance, 0) - COALESCE(prev_account_move_line.balance, 0))")
            else:
                return SQL("""
                    CASE WHEN prev_account_move_line.balance IS NULL THEN NULL
                         ELSE (COALESCE(current_account_move_lines.balance, 0) - COALESCE(prev_account_move_line.balance, 0)) / COALESCE(prev_account_move_line.balance, 1) * 100
                    END
                """)

    def action_audit_account(self):
        domain = [('account_id', 'in', self.ids)]
        working_file = self.env['account.return'].browse(self.env.context.get('working_file_id'))
        if working_file:
            domain += [('date', '>=', working_file.date_from), ('date', '<=', working_file.date_to)]
        return {
            **self.env['ir.actions.act_window']._for_xml_id("account.action_account_moves_all"),
            'domain': domain,
        }

    def _get_account_or_unaff_id_sql_redirection(self, audit, date_from, aml_alias="account_move_line", account_alias="account_account"):
        unaffected_earnings_accounts = self.env['account.account']._read_group(
            domain=[
                *self.env['account.account']._check_company_domain(audit.company_ids),
                ('account_type', '=', 'equity_unaffected'),
            ],
            groupby=['company_ids'],
            aggregates=['id:min'],
        )
        unaffected_earnings_accounts = {
            company.id: account_id
            for company, account_id in unaffected_earnings_accounts
        }

        return SQL(
            """
            CASE
                WHEN %(account_type)s ILIKE ANY(ARRAY[%(income_pattern)s, %(expense_pattern)s])
                    AND %(date_field)s < %(query_date_from)s
                THEN (
                        %(unaffected_earnings_accounts_per_company)s::jsonb
                        ->>(%(company_id_field)s::text)
                )::int
                ELSE %(account_id_field)s
            END
            """,
            account_type=SQL.identifier(account_alias, 'account_type'),
            income_pattern=r'income%',
            expense_pattern=r'expense%',
            date_field=SQL.identifier(aml_alias, 'date'),
            company_id_field=SQL.identifier(aml_alias, 'company_id'),
            query_date_from=date_from,  # Is different from audit date_from when computing previous balances
            unaffected_earnings_accounts_per_company=json.dumps(unaffected_earnings_accounts),
            account_id_field=SQL.identifier(aml_alias, 'account_id'),
        )
