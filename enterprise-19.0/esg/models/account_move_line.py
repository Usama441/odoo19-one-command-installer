from itertools import product

from odoo import api, fields, models
from odoo.fields import Domain
from odoo.tools.sql import column_exists, create_column


class AccountMoveLine(models.Model):
    _inherit = 'account.move.line'

    esg_emission_factor_id = fields.Many2one('esg.emission.factor', string='Emission Factor', compute='_compute_esg_emission_factor_id', store=True, readonly=False, index='btree_not_null')
    esg_uncertainty_value = fields.Float(string='Uncertainty (%)', related='esg_emission_factor_id.esg_uncertainty_value')
    esg_uncertainty_absolute_value = fields.Float(string='Uncertainty (kgCO₂e)', compute='_compute_esg_uncertainty_absolute_value')
    esg_emission_multiplicator = fields.Float(compute='_compute_esg_emission_multiplicator', store=True, export_string_translation=False)  # Technical field, storing the multiplicator to apply to the gas volumes (important for the report)
    esg_emissions_value = fields.Float(string='Emissions (kgCO₂e)', compute='_compute_esg_emissions_value')

    def _auto_init(self):
        if not column_exists(self.env.cr, "account_move_line", "esg_emission_factor_id"):
            # Create the column to avoid computation during installation
            create_column(self.env.cr, "account_move_line", "esg_emission_factor_id", "int4")
            create_column(self.env.cr, "account_move_line", "esg_emission_multiplicator", "float8")
        return super()._auto_init()

    @api.depends(
        'quantity', 'price_subtotal', 'esg_emission_factor_id.compute_method', 'esg_emission_factor_id.currency_id',
        'esg_emission_factor_id.uom_id', 'product_uom_id', 'currency_id', 'move_type', 'account_type',
    )
    def _compute_esg_emission_multiplicator(self):
        for line in self:
            if line.account_type not in ('expense', 'expense_other', 'expense_direct_cost', 'asset_fixed') or not line.esg_emission_factor_id:
                line.esg_emission_multiplicator = 0
            elif line.esg_emission_factor_id.compute_method == 'monetary':
                aml_currency = line.currency_id or line.company_id.currency_id
                if aml_currency and line.esg_emission_factor_id.currency_id:
                    line.esg_emission_multiplicator = line.price_subtotal * line.esg_emission_factor_id.currency_id._convert(1, aml_currency, date=line.date)
                else:
                    line.esg_emission_multiplicator = 0
            else:
                aml_uom = line.product_uom_id or line.esg_emission_factor_id.uom_id
                if aml_uom and line.esg_emission_factor_id.uom_id:
                    line.esg_emission_multiplicator = line.quantity * line.esg_emission_factor_id.uom_id._compute_quantity(1, aml_uom)
                else:
                    line.esg_emission_multiplicator = 0

            if line.move_type == 'in_refund':
                line.esg_emission_multiplicator *= -1

    @api.depends('esg_emission_multiplicator', 'esg_emission_factor_id.esg_emissions_value')
    def _compute_esg_emissions_value(self):
        for line in self:
            if line.account_type not in ('expense', 'expense_other', 'expense_direct_cost', 'asset_fixed'):
                line.esg_emissions_value = 0
            else:
                line.esg_emissions_value = line.esg_emission_factor_id.esg_emissions_value * line.esg_emission_multiplicator

    @api.depends('esg_emissions_value', 'esg_uncertainty_value')
    def _compute_esg_uncertainty_absolute_value(self):
        for line in self:
            if line.account_type not in ('expense', 'expense_other', 'expense_direct_cost', 'asset_fixed'):
                line.esg_uncertainty_absolute_value = 0
            else:
                line.esg_uncertainty_absolute_value = line.esg_emissions_value * line.esg_uncertainty_value

    @api.depends('product_id', 'account_id', 'partner_id')
    def _compute_esg_emission_factor_id(self):
        move_lines = self.filtered(lambda aml: aml.account_type in ('expense', 'expense_other', 'expense_direct_cost', 'asset_fixed'))
        if move_lines:
            move_lines._assign_factors_to_move_lines(no_match_reset=True)

    def _assign_factors_to_move_lines(self, factors=None, no_match_reset=False):
        domain = [
            '|', '|',
            ('product_id', 'in', self.product_id.ids),
            ('partner_id', 'in', self.partner_id.ids),
            ('account_id', 'in', self.account_id.ids),
        ]
        if factors:
            domain = Domain.AND([domain, [('esg_emission_factor_id', 'in', factors.ids)]])
        factor_per_rule = {
            (rule.product_id.id, rule.partner_id.id, rule.account_id.id): rule.esg_emission_factor_id.id
            for rule in self.env['esg.assignation.line'].search(domain)
        }

        modified_aml_ids = []
        for line in self:
            initial_rule = (line.product_id.id, line.partner_id.id, line.account_id.id)
            combinations = list(product(*[(v, False) for v in initial_rule]))
            assigned = False
            for rule in combinations:
                if rule in factor_per_rule:
                    line.esg_emission_factor_id = factor_per_rule[rule]
                    modified_aml_ids.append(line.id)
                    assigned = True
                    break
            if not assigned and (no_match_reset or line.esg_emission_factor_id in factors):
                line.esg_emission_factor_id = False
                modified_aml_ids.append(line.id)

        return tuple(modified_aml_ids)
