from odoo import models, fields
from odoo.tools import SQL


class AccountFollowupCustomHandler(models.AbstractModel):
    _name = 'account.followup.report.handler'
    _inherit = 'account.partner.ledger.report.handler'
    _description = 'Follow-Up Report Custom Handler'

    def _custom_options_initializer(self, report, options, previous_options):
        super()._custom_options_initializer(report, options, previous_options)

        options['buttons'].append({
            'name': self.env._('Send'),
            'action': 'action_send_follow_up',
            'sequence': 100,
            'always_show': True,
        })

        options['custom_display_config'].setdefault('components', {})['AccountReportLineCell'] = 'PartnerLedgerFollowupLineCell'

        if self.env.ref('account_reports.pdf_export_main_customer_report', raise_if_not_found=False):
            options['custom_display_config'].setdefault('pdf_export', {})['pdf_export_main'] = 'account_reports.pdf_export_main_customer_report'
            options['custom_display_config']['css_custom_class'] += ' customer_report'

        if len(options['partner_ids']) == 1 and not (options.get('export_mode') == 'print' and options.get('export_format') == 'pdf'):
            options['ignore_totals_below_sections'] = True

        if options['report_id'] != previous_options.get('report_id') and options['export_mode'] != 'print':
            options['unreconciled'] = True

        if options['export_mode'] == 'print':
            # When printing the report, we don't want to include `no_followup` lines.
            options['forced_domain'] = options.get('forced_domain', []) + [('no_followup', '=', False)]
            options['columns'] = [col for col in options['columns'] if col['expression_label'] != 'no_followup']

            if options.get('export_format') == 'pdf':
                options['column_headers'] = []  # date will already be included in the PDF header
                options['unfold_all'] = True  # lines are computed once for all the partners, then split into one document per partner

        if (not previous_options or not previous_options.get('account_type')):
            for opt in options['account_type']:
                if opt['id'] in ('trade_receivable', 'trade_payable'):
                    opt['selected'] = True
                else:
                    opt['selected'] = False

    def _get_partner_ledger_query(self, options, date_scope, match_partner_on_partials=True):
        query = super()._get_partner_ledger_query(options, date_scope, match_partner_on_partials=False)
        query.add_where(SQL(
            "(%s != 0 OR %s != 0)",
            query.table.amount_residual,
            query.table.amount_residual_currency,
        ))
        return query

    def _get_subformulas_rules(self):
        subformula_rules = super()._get_subformulas_rules()
        return subformula_rules | {
            'amount': {'field': 'balance'}
        }

    def _get_date_order_clause(self, query, groupbys, date_from):
        return [
            SQL('%s ASC NULLS LAST', self._get_agg_expr('date_maturity', query, groupbys, date_from)),
            *super()._get_date_order_clause(query, groupbys, date_from),
        ]

    def _get_documents_to_print(self, report, options, lines):
        return self._get_documents_to_print_per_partner(report, options, lines, 'amount_residual')

    def action_send_follow_up(self, options):
        template = self.env.ref('account_reports.email_template_customer_follow_up_report', False)
        partners = self.env['res.partner'].browse(options.get('partner_ids', []))
        return {
            'name': self.env._("Send Reminder to %s", partners.name) if len(partners) == 1 else self.env._("Send Reminders"),
            'type': 'ir.actions.act_window',
            'views': [[False, 'form']],
            'res_model': 'account.report.send',
            'target': 'new',
            'context': {
                'default_mail_template_id': template.id,
                'default_report_options': options,
            },
        }

    def _get_partner_report_filename(self, report, partner, options):
        today = fields.Date.context_today(report).strftime('%m%d%Y')
        return f"{today}_Customer-Statement.pdf"
