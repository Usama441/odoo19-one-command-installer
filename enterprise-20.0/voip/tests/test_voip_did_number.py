from unittest.mock import patch

from odoo.tests import common, tagged
from odoo.tests.common import new_test_user
from odoo.tools import html2plaintext

from odoo.addons.voip.models.phone_service_api import PhoneServiceAPI
from odoo.addons.voip.tests.common_voip import (
    forbid_phone_service_http,
    mock_pbx_layer,
    pbx_router,
)


def _mock_phone_service(route, params, retry_registration=True):
    return pbx_router(route, params)


def _patch_phone_service():
    return patch.object(
        PhoneServiceAPI, "_call_phone_service", side_effect=_mock_phone_service,
    )


@tagged("voip")
class TestVoipDidNumberEmail(common.TransactionCase):
    STATE_MESSAGES = [
        ("active", "Your number is active! (%s)", "Your number is now active and you can assign it."),
        ("failure", "Your number order has failed (%s)", "could not be completed."),
        ("pending", "Your number order is under review (%s)", "has been received and is under review."),
        ("suspended", "Your number is suspended (%s)", "Buy credits to reactivate it"),
        ("released", "Your number has been released (%s)", "It is no longer yours"),
    ]

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.country_be = cls.env.ref("base.be")
        existing = cls.env["voip.did.number"].search([]).with_context(
            voip_skip_pbx_sync=True,
        )
        existing.write({"state": "released"})
        existing.unlink()

    def setUp(self):
        super().setUp()
        forbid_phone_service_http(self)
        mock_pbx_layer(self)

    def _new_did(self, state="ordering", did_number="+3287000001"):
        did = self.env["voip.did.number"].sudo().create({
            "did_number": did_number,
            "did_number_type": "local",
            "state": state,
            "country_id": self.country_be.id,
        })
        # create() leaves a "tracking disabled" marker (None) in precommit
        # data that would swallow the next write's tracking; flush callbacks
        # now like a transaction commit would (TransactionCase never commits).
        self.env.cr.precommit.run()
        return did

    def _subscribe_email_follower(self, did, login="voip_email_follower"):
        user = new_test_user(
            self.env,
            login=login,
            context={"no_reset_password": True},
            notification_type="email",
        )
        user.partner_id.email = "%s@example.com" % login
        did.sudo().message_subscribe(partner_ids=[user.partner_id.id])
        return user

    def _set_did_state(self, did, state):
        did.sudo().write({"state": state})
        # Tracking messages are generated in a precommit callback. TransactionCase never commits, flush the callbacks manually.
        self.env.cr.precommit.run()

    def _notification_mails(self, did):
        return self.env["mail.mail"].sudo().search([
            ("mail_message_id.model", "=", "voip.did.number"),
            ("mail_message_id.res_id", "=", did.id),
            ("body_html", "!=", False),
        ], order="id desc")

    def _assert_email_body(self, did, expected_text):
        mails = self._notification_mails(did)
        mail_bodies = [html2plaintext(mail.body_html) for mail in mails]
        self.assertTrue(
            mails,
            "No notification email was generated for the DID state change "
            "(tracking message or notification pipeline failed)",
        )
        self.assertTrue(
            any(expected_text in body for body in mail_bodies),
            "Expected %r in notification email body, got:\n%s" % (
                expected_text,
                "\n---\n".join(mail_bodies),
            ),
        )

    def test_voip_did_email_button_shows_view_phone_number(self):
        did = self._new_did()
        self._subscribe_email_follower(did)
        self._set_did_state(did, "active")
        self._assert_email_body(did, "View Phone Number")

    def test_voip_did_state_changes_generate_correct_email_messages(self):
        for index, (state, expected_subject, expected_body) in enumerate(self.STATE_MESSAGES):
            with self.subTest(state=state):
                did = self._new_did(did_number="+32870001%02d" % index)
                self._subscribe_email_follower(
                    did, login="voip_email_follower_%d" % index,
                )
                self._set_did_state(did, state)
                self.assertEqual(self._notification_mails(did)[0].subject, expected_subject % did.did_number)
                self._assert_email_body(did, expected_body)
                self._assert_email_body(did, "Dear %s," % did.create_uid.name)

    def test_voip_did_state_email_greets_assigned_user(self):
        did = self._new_did()
        user = self._subscribe_email_follower(did)
        did.sudo().destination_ref = user
        self._set_did_state(did, "active")
        self._assert_email_body(did, "Dear %s," % user.name)

    def test_voip_did_state_message_keeps_explicit_subject(self):
        did = self._new_did()
        did.sudo().state = "active"
        message = did.message_post(
            subject="Custom subject",
            message_type="tracking",
            subtype_id=self.env.ref("voip.mt_did_number_state").id,
        )
        self.assertEqual(message.subject, "Custom subject")
