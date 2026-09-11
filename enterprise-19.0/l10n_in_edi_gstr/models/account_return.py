from odoo import fields, models


class AccountReturn(models.Model):
    _inherit = 'account.return'

    l10n_in_gstr1_include_einvoice = fields.Boolean(
        string="E-Invoice in GSTR-1",
        help="Enable this option to include invoice with generated E-invoices being pushing to GSTR-1.",
        tracking=True
    )
    l10n_in_gst_efiling_feature_enabled = fields.Boolean(related='company_id.l10n_in_gst_efiling_feature')
    l10n_in_edi_feature_enabled = fields.Boolean(related='company_id.l10n_in_edi_feature')
    l10n_in_hide_include_einvoice = fields.Boolean(compute='_compute_l10n_in_hide_include_einvoice')

    def _compute_l10n_in_hide_include_einvoice(self):
        for record in self:
            record.l10n_in_hide_include_einvoice = record.type_id._get_periodicity(record.company_id) == 'trimester'

    def is_einvoice_skippable(self, move_id):
        # Check if the skip e-invoice condition is met for a given move_id.
        return (
            not self.l10n_in_gstr1_include_einvoice
            and move_id.l10n_in_edi_status in ['sent', 'cancelled']
        )

    def _build_open_invoice_records_action(self, name, move_ids):
        return {
            'type': 'ir.actions.act_window',
            'name': name,
            'res_model': 'account.move',
            'views': [
                (self.env.ref('account.view_out_invoice_tree').id, 'list'),
                (self.env.ref('account.view_move_form').id, 'form'),
            ],
            'domain': [('id', 'in', move_ids)],
            'context': {
                'create': False,
                'delete': False,
                'expand': True,
            },
        }

    def _check_suite_in_gstr1_report(self, check_codes_to_ignore):
        _ = self.env._
        checks = super()._check_suite_in_gstr1_report(check_codes_to_ignore)
        options = self._get_closing_report_options()

        if not self.l10n_in_edi_feature_enabled:
            check_codes_to_ignore.add('missing_einvoice')
            self.check_ids.filtered(lambda check: check.code == 'missing_einvoice').unlink()

        # Get the eligible invoices that are not e-invoiced
        domain = [
            ("date", ">=", options["date"]["date_from"]),
            ("date", "<=", options["date"]["date_to"]),
            ("journal_id.type", "=", "sale"),
            ("state", "=", "posted"),
            ("l10n_in_edi_status", "not in", ["sent", "cancelled"]),
        ]

        # Check for all invoices should have been e-invoiced
        if 'missing_einvoice' not in check_codes_to_ignore:
            sale_section_exceptions = {
                "sale_b2cl", "sale_b2cs",
                "sale_cdnur_b2cl", "sale_nil_rated",
                "sale_exempt", "sale_non_gst_supplies",
                "sale_eco_9_5", "sale_out_of_scope",
            }
            eligible_move = self.env['account.move'].search(domain)
            move_ids = eligible_move.filtered(lambda move: any(
                line.display_type == 'product'
                and line.l10n_in_gstr_section
                and line.l10n_in_gstr_section.startswith('sale_')
                and line.l10n_in_gstr_section not in sale_section_exceptions
                for line in move.line_ids
            )).ids
            checks.append({
                'code': 'missing_einvoice',
                'name': _("Missing E-Invoice"),
                'message': _("Some invoices are missing e-invoice."),
                'records_name': _("Invoice") if len(move_ids) == 1 else _("Invoices"),
                'records_count': len(move_ids),
                'result': 'anomaly' if move_ids else 'reviewed',
                'action': self._build_open_invoice_records_action(_('Missing E-Invoice'), move_ids),
                })
        return checks
