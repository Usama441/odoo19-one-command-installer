# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import api, fields, models
from odoo.exceptions import UserError
from odoo.fields import Domain

ASSET_TRACKED_FIELDS = {'asset_depreciation_account_id', 'asset_expense_account_id', 'depreciation_model_id'}


class AccountAccount(models.Model):
    _inherit = 'account.account'

    can_create_asset = fields.Boolean(compute="_compute_can_create_asset")
    asset_depreciation_account_id = fields.Many2one(
        comodel_name='account.account',
        string='Accumulated Depreciation',
        domain=[
            ('account_type', 'in', ('asset_fixed', 'asset_non_current')),
        ],
        help="Account used in the depreciation entries, to decrease the asset value.",
        tracking=True,
    )
    asset_expense_account_id = fields.Many2one(
        comodel_name='account.account',
        domain=[('account_type', 'in', ('expense_depreciation', 'expense'))],
        help="Account used in the periodical entries, to record a part of the asset as expense.",
        tracking=True,
    )
    depreciation_model_id = fields.Many2one(
        comodel_name='account.depreciation.model',
        domain=Domain.OR([Domain('journal_id', '=', False), Domain('journal_id.journal_group_id', '=', False)]),
        help="Default depreciation model to use on a vendor bill or a refund",
        tracking=True,
    )
    ledger_depreciation_model_ids = fields.Many2many(
        comodel_name='account.depreciation.model',
        domain=[('journal_id.journal_group_id', '!=', False)],
    )
    display_asset_accounts = fields.Boolean(compute="_compute_display_asset_accounts")

    asset_properties_definition = fields.PropertiesDefinition('Asset Account Properties')

    @api.depends('account_type')
    def _compute_can_create_asset(self):
        for account in self:
            account.can_create_asset = (
                account.account_type == 'asset_fixed'
            )

    @api.depends('depreciation_model_id', 'can_create_asset')
    def _compute_display_asset_accounts(self):
        for account in self:
            account.display_asset_accounts = (
                account.can_create_asset
                and account.depreciation_model_id
                and account.depreciation_model_id.method != 'no_depreciation'
            )

    def _track_execute(self, track_init_values, trackings, track_records=None):
        # Only track the asset configuration of accounts already linked to an asset
        if not track_records and (asset_changed_ids := {
            account_id
            for account_id, (changes, _tracking_values) in trackings.items()
            if ASSET_TRACKED_FIELDS.intersection(changes)
        }):
            unused_account_ids = asset_changed_ids - {
                account.id
                for [account] in self.env['account.asset'].sudo().with_context(active_test=False)._read_group(
                    domain=[('account_asset_id', 'in', list(asset_changed_ids))],
                    groupby=['account_asset_id'],
                )
            }
            trackings = {
                account_id: (
                    set(changes) - ASSET_TRACKED_FIELDS,
                    [value for value in tracking_values if value.get('field_name') not in ASSET_TRACKED_FIELDS],
                ) if account_id in unused_account_ids else (changes, tracking_values)
                for account_id, (changes, tracking_values) in trackings.items()
            }
        return super()._track_execute(track_init_values, trackings, track_records=track_records)

    def _should_display_asset_tag(self):
        return super()._should_display_asset_tag() or (self.depreciation_model_id and self.env.context.get('from_bill'))

    @api.constrains('ledger_depreciation_model_ids')
    def _check_unique_ledger_depreciation(self):
        for account in self:
            if account.ledger_depreciation_model_ids.filtered(lambda l: not l.journal_id.journal_group_id):
                raise UserError(self.env._("Depreciation model must contain journals that belong to an explicit ledger."))
            if len(account.ledger_depreciation_model_ids) != len(account.ledger_depreciation_model_ids.journal_id.journal_group_id):
                raise UserError(self.env._("The same ledger cannot be linked multiple times on the same account."))
