from odoo import models


class CustomerStatementTRHandler(models.AbstractModel):
    _inherit = 'account.customer.statement.report.handler'

    def action_send_statements(self, options):
        action = super().action_send_statements(options)
        if self.env.company.account_fiscal_country_id.code == 'TR':
            template = self.env.ref(
                'l10n_tr_reports.email_template_reconciliation_letter',
                raise_if_not_found=False,
            )
            if template:
                action['context']['default_mail_template_id'] = template.id

        return action

    def _get_pdf_export_html(self, options, lines, additional_context=None, template=None):
        partner_ids = options.get('partner_ids') or []
        if (
            self.env.company.account_fiscal_country_id.code == 'TR'
            and len(partner_ids) == 1 and partner_ids[0]
        ):
            partner = self.env['res.partner'].browse(partner_ids)
            invoice_count = sum(1 for line in lines if line.level == 4 and line.groupby is None)

            additional_context.update({
                'reconciliation_letter': True,
                'partner_name': partner.name,
                'is_turkish': (
                    partner.lang == 'tr_TR'
                    or self.env.user.lang == 'tr_TR'
                ),
                'invoice_count': invoice_count,
            })

        return self.env['account.report'].browse(options['report_id'])._get_pdf_export_html(
            options,
            lines,
            additional_context,
            template,
        )
