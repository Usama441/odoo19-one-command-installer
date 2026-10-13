from odoo.tests import Form, tagged

from odoo.addons.base.tests.common import BaseCommon


@tagged('-at_install', 'post_install')
class TestHelpdeskSaleWarning(BaseCommon):
    """ The warning lives in helpdesk_sale, but it is only displayed for teams with
    `use_helpdesk_sale_timesheet`, which installs this module when enabled. """
    _test_user_groups = ('helpdesk.group_helpdesk_user',)

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.group_warning_sale = cls.quick_ref('sale.group_warning_sale')
        cls.group_user._apply_group(cls.group_warning_sale)

        cls.partner_with_warning = cls.env['res.partner'].create({
            'name': 'Partner With Warning',
            'sale_warn_msg': 'Highly infectious disease',
        })
        # No name on purpose: the warning falls back on the display name.
        cls.child_partner_with_warning = cls.env['res.partner'].create({
            'type': 'invoice',
            'parent_id': cls.partner_with_warning.id,
            'sale_warn_msg': 'Slightly infectious disease',
        })
        cls.billable_team, cls.non_billable_team = cls.env['helpdesk.team'].create([
            {
                'name': 'Billable Team',
                'use_helpdesk_timesheet': True,
                'use_helpdesk_sale_timesheet': True,
            },
            {
                'name': 'Non-billable Team',
            },
        ])
        cls.partner_warning = "Partner With Warning - Highly infectious disease"
        cls.child_partner_warning = (
            "Partner With Warning, Invoice - Slightly infectious disease\n"
            "Partner With Warning - Highly infectious disease"
        )

    def test_ticket_sale_warning_text(self):
        billable_ticket, non_billable_ticket = self.env['helpdesk.ticket'].create([
            {
                'name': 'Billable Ticket',
                'team_id': self.billable_team.id,
                'partner_id': self.partner_with_warning.id,
            },
            {
                'name': 'Non-billable Ticket',
                'team_id': self.non_billable_team.id,
                'partner_id': self.partner_with_warning.id,
            },
        ])
        self.assertEqual(
            billable_ticket.sale_warning_text,
            self.partner_warning,
            "The ticket of a team with time billing should display the sale warning of its customer.",
        )
        self.assertFalse(
            non_billable_ticket.sale_warning_text,
            "No warning should be displayed on tickets of teams without time billing.",
        )

        billable_ticket.partner_id = self.child_partner_with_warning
        self.assertEqual(
            billable_ticket.sale_warning_text,
            self.child_partner_warning,
            "The warning of the parent partner should be displayed after the one of its contact.",
        )

        billable_ticket.partner_id = self.partner
        self.assertFalse(
            billable_ticket.sale_warning_text,
            "No warning should be displayed for a customer without sale warning.",
        )

    def test_ticket_sale_warning_text_form(self):
        with Form(self.env['helpdesk.ticket']) as ticket_form:
            ticket_form.name = 'Ticket'
            ticket_form.team_id = self.billable_team
            ticket_form.partner_id = self.partner_with_warning
            self.assertEqual(
                ticket_form.sale_warning_text,
                self.partner_warning,
                "The warning should be displayed as soon as the customer is set in the form.",
            )

            ticket_form.team_id = self.non_billable_team
            self.assertFalse(
                ticket_form.sale_warning_text,
                "The warning should be hidden when moving the ticket to a team without time billing.",
            )

            ticket_form.team_id = self.billable_team
            self.assertEqual(
                ticket_form.sale_warning_text,
                self.partner_warning,
                "The warning should be displayed again when moving the ticket back to a team with time billing.",
            )

    def test_ticket_sale_warning_text_without_warning_group(self):
        self.group_user.sudo()._remove_group(self.group_warning_sale)
        ticket = self.env['helpdesk.ticket'].create({
            'name': 'Ticket',
            'team_id': self.billable_team.id,
            'partner_id': self.child_partner_with_warning.id,
        })
        self.assertFalse(
            ticket.sale_warning_text,
            "No warning should be displayed without the sale warning group.",
        )
