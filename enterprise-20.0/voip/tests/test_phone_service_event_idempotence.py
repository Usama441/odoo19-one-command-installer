from contextlib import contextmanager
from datetime import datetime
from unittest.mock import patch

from odoo.tests import tagged

from odoo.addons.mail.models.mail_thread import MailThread
from odoo.addons.voip.models.voip_call import VoipCall

from .pbx_stream import HANGUP_CALL_REJECTED
from .test_phone_service_event import PhoneServiceEventCase

# Taken before setUp patches it to record the pushes.
NOTIFY_DEVICES_SEND = VoipCall._notify_devices_send


@contextmanager
def emitted_at(conversation, stamp):
    """Emit what the block sends at ``stamp``: a late copy of an event carries
    the instant it happened, not the one it arrives at."""
    now = conversation.clock.now
    conversation.clock.now = datetime.fromisoformat(stamp)
    try:
        yield
    finally:
        conversation.clock.now = now


@tagged("-at_install", "post_install")
class TestRepeatedCallEvents(PhoneServiceEventCase):
    """The PBX may report the same fact twice, under another event id, and in
    any order: each call event must settle the call once."""

    def test_a_call_created_again_while_ringing_changes_nothing(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        ring.leg("bernard").created()

        self.assertOutcome({"bernard": {"state": "calling"}})
        self.assertEqual(len(self.call_of("bernard").leg_ids), 1)

    def test_a_call_created_again_after_the_end_changes_nothing(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        ring.leg("bernard").answers()
        ring.wait(10)
        ring.leg("bernard").ends(answered=True)
        call = self.call_of("bernard")
        self.clearPushes()

        ring.leg("bernard").created()

        self.assertOutcome({"bernard": {"state": "terminated", "duration": 10}})
        self.assertEqual(self.call_of("bernard"), call)
        self.assertEqual(call.leg_ids.voip_call_id, call, "the leg stays on its call")
        self.assertNotIn(("bernard", "calling"), self.pushes, "nothing rings again")

    def test_a_mobile_leg_created_again_after_the_end_changes_nothing(self):
        # A member woken by push is reached on a dial_mobile channel, which
        # carries no SIP Call-ID to find its call by.
        ring = self.inbound_ring()
        ring.push("bernard")
        mobile = ring.mobile_leg("bernard")
        mobile.created()
        ring.wait(15)
        ring.cancel_push("bernard")
        mobile.ends()
        self.clearPushes()

        mobile.created()

        self.assertOutcome({"bernard": {"state": "missed"}})
        self.assertNotIn(("bernard", "calling"), self.pushes, "nothing rings again")

    def test_a_call_answered_again_while_ongoing_changes_nothing(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        ring.leg("bernard").answers()
        answered_at = ring.answered_at
        with emitted_at(ring, answered_at):
            ring.leg("bernard").answers()
        ring.wait(10)
        ring.leg("bernard").ends(answered=True)

        self.assertOutcome({"bernard": {"state": "terminated", "duration": 10}})

    def test_a_call_answered_again_after_the_end_keeps_its_duration(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        ring.leg("bernard").answers()
        answered_at = ring.answered_at
        ring.wait(25)
        ring.leg("bernard").ends(answered=True)

        with emitted_at(ring, answered_at):
            ring.leg("bernard").answers()

        self.assertOutcome({"bernard": {"state": "terminated", "duration": 25}})
        self.assertEqual(self.call_of("bernard").start_date, ring.answered_at_naive)

    def test_an_end_received_before_its_answer_still_counts_the_duration(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        ring.answered_at = answered_at = ring.clock.stamp
        ring.wait(25)
        ring.leg("bernard").ends(answered=True)

        with emitted_at(ring, answered_at):
            ring.leg("bernard").answers()

        self.assertOutcome({"bernard": {"state": "terminated", "duration": 25}})
        self.assertEqual(self.call_of("bernard").start_date, ring.answered_at_naive)

    def test_a_late_answer_does_not_revive_an_unanswered_call(self):
        for state, end in (
            ("missed", {}),
            ("rejected", {"cause": HANGUP_CALL_REJECTED}),
        ):
            with self.subTest(state=state):
                self.reset_calls()
                ring = self.inbound_ring(conversation_id=f"conv-late-answer-{state}")
                ring.leg("bernard").created()
                ring.wait(15)
                ring.leg("bernard").ends(**end)

                with emitted_at(ring, ring.clock.stamp):
                    ring.leg("bernard").answers()

                self.assertOutcome({"bernard": {"state": state, "start_date": False}})

    def test_connected_line_updates_apply_in_the_order_they_happened(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        ring.leg("bernard").answers()
        first_update = ring.clock.tick(5)
        second_update = ring.clock.tick(5)

        # The later transfer target arrives first.
        with emitted_at(ring, second_update):
            ring.leg("bernard").updated(status="Up", peer_caller_id_number="+3228000002")
        with emitted_at(ring, first_update):
            ring.leg("bernard").updated(status="Up", peer_caller_id_number="+3228000001")

        self.assertOutcome({"bernard": {"state": "ongoing", "phone_number": "+3228000002"}})


@tagged("-at_install", "post_install")
class TestRepeatedPushEvents(PhoneServiceEventCase):
    """A push and its cancel may each arrive twice, or the wrong way round."""

    def _repeat_push(self, ring, login):
        """The same push again, under another event id."""
        ring.emit("odoo_call_push_notification", ring.member(login).push_payload)

    def test_a_push_received_again_while_ringing_changes_nothing(self):
        ring = self.inbound_ring()
        ring.push("bernard")
        self._repeat_push(ring, "bernard")

        self.assertOutcome({"bernard": {"state": "calling"}})

    def test_a_push_received_again_after_its_cancel_rings_nothing(self):
        ring = self.inbound_ring()
        ring.push("bernard")
        ring.wait(15)
        ring.cancel_push("bernard")
        self.clearPushes()

        self._repeat_push(ring, "bernard")

        self.assertOutcome({"bernard": {"state": "missed"}})
        self.assertNotIn(("bernard", "calling"), self.pushes, "nothing rings again")

    def test_a_push_received_after_its_cancel_rings_nothing(self):
        ring = self.inbound_ring()
        ring.cancel_push("bernard")
        ring.push("bernard")

        self.assertFalse(
            self.call_of("bernard").filtered(lambda call: call.state == "calling"),
            "no call is left ringing")
        self.assertNotIn(("bernard", "calling"), self.pushes, "nothing rings")

    def test_a_new_ring_after_a_cancel_still_rings(self):
        # A queue retrying the same caller rings the member again in the same
        # conversation, through the same caller channel.
        ring = self.direct_ring()
        ring.push("bernard")
        ring.wait(15)
        ring.cancel_push("bernard")
        ring.wait(5)
        self.clearPushes()

        ring.push("bernard")

        self.assertEqual(self.call_of("bernard").mapped("state"), ["missed", "calling"])
        self.assertEqual(self.pushes, [("bernard", "calling")])

    def test_a_cancel_received_again_changes_nothing(self):
        ring = self.inbound_ring()
        ring.push("bernard")
        ring.wait(15)
        ring.cancel_push("bernard")
        ring.cancel_push("bernard")

        self.assertOutcome({"bernard": {"state": "missed"}})
        self.assertEqual(self.pushes.count(("bernard", "missed")), 1)


@tagged("-at_install", "post_install")
class TestEventSideEffects(PhoneServiceEventCase):
    """What a handler sends outside its transaction must not outlive it."""

    def test_a_push_leaves_once_the_event_is_committed(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        mark = len(self.pushes)
        event = self.PhoneServiceEvent._register_event(
            "conv-1:late-answer", "call_answered", ring.leg("bernard")._payload(status="Up"),
            self.PhoneServiceEvent._parse_naive_utc(ring.clock.stamp))

        event._process_event()
        self.assertPushesSince(mark, [])
        self.env.cr.postcommit.run()
        self.assertPushesSince(mark, [("bernard", "ongoing")])

    def test_a_rolled_back_event_sends_no_push(self):
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        mark = len(self.pushes)
        event = self.PhoneServiceEvent._register_event(
            "conv-1:failed-answer", "call_answered", ring.leg("bernard")._payload(status="Up"),
            self.PhoneServiceEvent._parse_naive_utc(ring.clock.stamp))

        with (
            patch.object(
                self.registry["voip.phone.service.event"], "_complete_ringing_peers",
                side_effect=ValueError("processing failed after the push")),
            self.assertRaises(ValueError),
            self.env.cr.savepoint(),
        ):
            event._process_event()
        self.assertEqual(self.pushes[mark:], [], "nothing leaves during the processing")
        # What the rollback of the event's transaction does (see Cursor.rollback);
        # a test cannot roll its own cursor back.
        self.env.cr.postcommit.clear()
        self.env.cr.postcommit.run()

        self.assertOutcome({"bernard": {"state": "calling"}})
        self.assertPushesSince(mark, [])

    def test_a_push_reaches_the_devices_of_a_webhook_event(self):
        # The webhook processes its events as the public user, on sudo records;
        # the push sent after commit must not lose that sudo on its new cursor.
        self.env["ir.config_parameter"].sudo().set_str("mail.web_push_vapid_private_key", "private")
        self.env["ir.config_parameter"].sudo().set_str("mail.web_push_vapid_public_key", "public")
        device = self.env["mail.push.device"].sudo().create({
            "partner_id": self.user.partner_id.id,
            "endpoint": "https://push.example.com/bernard",
            "keys": '{"p256dh": "p256dh", "auth": "auth"}',
        })
        ring = self.inbound_ring()
        ring.leg("bernard").created()
        event = self.PhoneServiceEvent._register_event(
            "conv-1:webhook-answer", "call_answered", ring.leg("bernard")._payload(status="Up"),
            self.PhoneServiceEvent._parse_naive_utc(ring.clock.stamp))

        with (
            patch.object(VoipCall, "_notify_devices_send", NOTIFY_DEVICES_SEND),
            patch.object(MailThread, "_web_push_send_notification") as send,
        ):
            event.with_user(self.env.ref("base.public_user")).sudo()._process_event()
            self.env.cr.postcommit.run()

        send.assert_called_once()
        self.assertEqual(send.call_args.args[0], device)
        self.assertEqual(send.call_args.kwargs["payload"]["options"]["data"]["call_state"], "ongoing")
