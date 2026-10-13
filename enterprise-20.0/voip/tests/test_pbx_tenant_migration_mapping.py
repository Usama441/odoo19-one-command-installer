from types import SimpleNamespace
from unittest.mock import patch

from werkzeug.exceptions import Forbidden

from odoo import Command
from odoo.exceptions import ValidationError
from odoo.tests import new_test_user, tagged
from odoo.tools import BinaryBytes, mute_logger

from odoo.addons.voip.controllers.phone_service_api_controller import PhoneServiceApiController
from odoo.addons.voip.tools.wav import encode_wav, pack_int16_samples
from odoo.addons.voip.models.phone_service_api import CLIENT_SECRET_PARAM, CLIENT_UUID_PARAM

from .common_voip import VoipPhoneServiceCase, capture_pbx_calls


CONTROLLER_PATH = "odoo.addons.voip.controllers.phone_service_api_controller"


def _wav_data(value=0):
    return BinaryBytes(encode_wav(
        pack_int16_samples([value] * 8),
        channels=1,
        sample_width=2,
        frame_rate=8000,
    ))


@tagged("voip", "post_install", "-at_install")
class TestApplyTenantMigrationMapping(VoipPhoneServiceCase):
    """Covers voip.pbx.service._apply_tenant_migration_mapping: the counterpart
    of phone_service_pbx_tenant_migration.py's action_notify_client_mapping,
    applying the destination PBX's ids before phone_service may switch this
    database's tenant over to it."""

    def _create_user(self, login, name=None):
        user = new_test_user(
            self.env,
            login=login,
            name=name or login.title(),
            voip_username=f"{login}-sip",
            voip_secret=f"{login}-sip-secret",
        )
        user.res_users_settings_id.with_context(
            voip_skip_config_bus=True,
            voip_skip_pbx_sync=True,
        ).voip_provider_id = self.env.ref("voip.odoo_provider")
        return user

    def _create_sound(self, name, value=0):
        return self.env["voip.sound"].with_context(voip_skip_pbx_sync=True).create({
            "name": name,
            "source_type": "upload",
            "data": _wav_data(value),
            "data_filename": f"{name.lower().replace(' ', '_')}.wav",
        })

    def setUp(self):
        super().setUp()
        parameters = self.env["ir.config_parameter"].sudo()
        parameters.set_str(CLIENT_UUID_PARAM, "migration-client-uuid")
        parameters.set_str(CLIENT_SECRET_PARAM, "migration-client-secret")
        self.user = self._create_user("migrated-agent", "Migrated Agent")
        self.user.with_context(voip_skip_pbx_sync=True).write({
            "voip_pbx_agent_id": 1,
            "voip_pbx_line_id": 2,
            "voip_pbx_user_id": 3,
            "voip_pbx_user_uuid": "source-user-uuid",
        })
        self.extension = self.env["voip.extension"].with_context(
            voip_skip_pbx_sync=True,
        ).create({
            "number": "4301",
            "destination_ref": f"res.users,{self.user.id}",
            "pbx_extension_id": 4,
        })
        self.voicemail = self.env["voip.voicemail"].with_context(
            voip_skip_pbx_sync=True,
        ).create({
            "name": "Migrated mailbox",
            "pbx_voicemail_id": 5,
        })
        self.call_group = self.env["voip.call.group"].with_context(
            voip_skip_pbx_sync=True,
        ).create({
            "name": "Migrated group",
            "pbx_group_id": 6,
            "pbx_group_uuid": "source-group-uuid",
        })
        self.queue = self.env["voip.queue"].with_context(voip_skip_pbx_sync=True).create({
            "name": "Migrated queue",
            "pbx_queue_id": 7,
        })
        sound = self._create_sound("Migrated menu sound")
        self.ivr = self.env["voip.ivr"].with_context(voip_skip_pbx_sync=True).create({
            "name": "Migrated menu",
            "menu_sound_id": sound.id,
            "pbx_ivr_id": 8,
        })
        self.time_condition = self.env["voip.time.condition"].with_context(
            voip_skip_pbx_sync=True,
        ).create({
            "name": "Migrated hours",
            "timezone": "Europe/Brussels",
            "pbx_schedule_id": 9,
            "period_ids": [Command.create({
                "mode": "open",
                "all_day": False,
                "hours_start": 8.0,
                "hours_end": 17.0,
                "week_days": "1-5",
            })],
        })
        self.did = self.env["voip.did.number"].with_context(voip_skip_pbx_sync=True).create({
            "did_number": "+3287000410",
            "destination_ref": f"res.users,{self.user.id}",
            "did_number_type": "local",
            "pbx_incall_id": 10,
            "pbx_incall_extension_id": 11,
        })
        self.music_on_hold = self.env["voip.music.on.hold"].with_context(
            voip_skip_pbx_sync=True,
        ).create({
            "name": "Migrated waiting music",
            "sort": "random_start",
            "pbx_moh_uuid": "source-moh-uuid",
            "pbx_moh_name": "source-moh-name",
        })

    def _resources(self):
        return {
            "users": [{
                "odoo_id": self.user.id,
                "user_id": 103,
                "user_uuid": "destination-user-uuid",
                "line_id": 102,
            }],
            "agents": [{"user_odoo_id": self.user.id, "agent_id": 101}],
            "extensions": [{"odoo_id": self.extension.id, "extension_id": 104}],
            "voicemails": [{"odoo_id": self.voicemail.id, "voicemail_id": 105}],
            "groups": [{
                "odoo_id": self.call_group.id,
                "group_id": 106,
                "group_uuid": "destination-group-uuid",
            }],
            "queues": [{"odoo_id": self.queue.id, "queue_id": 107}],
            "ivrs": [{"odoo_id": self.ivr.id, "ivr_id": 108}],
            "schedules": [{"odoo_id": self.time_condition.id, "schedule_id": 109}],
            "incalls": [{
                "odoo_id": self.did.id,
                "incall_id": 110,
                "extension_id": 111,
            }],
            "music_on_holds": [{
                "odoo_id": self.music_on_hold.id,
                "moh_uuid": "destination-moh-uuid",
                "moh_name": "destination-moh-name",
            }],
        }

    def _assert_mapping_applied(self):
        self.assertEqual(self.user.voip_pbx_agent_id, 101)
        self.assertEqual(self.user.voip_pbx_user_id, 103)
        self.assertEqual(self.user.voip_pbx_user_uuid, "destination-user-uuid")
        self.assertEqual(self.user.voip_pbx_line_id, 102)
        self.assertEqual(self.extension.pbx_extension_id, 104)
        self.assertEqual(self.voicemail.pbx_voicemail_id, 105)
        self.assertEqual(self.call_group.pbx_group_id, 106)
        self.assertEqual(self.call_group.pbx_group_uuid, "destination-group-uuid")
        self.assertEqual(self.queue.pbx_queue_id, 107)
        self.assertEqual(self.ivr.pbx_ivr_id, 108)
        self.assertEqual(self.time_condition.pbx_schedule_id, 109)
        self.assertEqual(self.did.pbx_incall_id, 110)
        self.assertEqual(self.did.pbx_incall_extension_id, 111)
        self.assertEqual(self.music_on_hold.pbx_moh_uuid, "destination-moh-uuid")
        self.assertEqual(self.music_on_hold.pbx_moh_name, "destination-moh-name")

    def test_applies_every_resource_type_without_calling_the_pbx(self):
        calls, patcher = capture_pbx_calls()
        with patcher:
            self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, self._resources())

        self._assert_mapping_applied()
        # Recording ids the migration already established on the destination
        # must never re-trigger a sync back to it.
        self.assertFalse(calls)

    def test_reapplying_the_same_mapping_is_idempotent(self):
        resources = self._resources()
        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)
        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)

        self._assert_mapping_applied()

    def test_skips_an_entry_whose_record_no_longer_exists(self):
        resources = self._resources()
        self.extension.with_context(voip_skip_pbx_sync=True).unlink()

        # Must not raise despite one entry now pointing at a deleted record.
        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)

        self.assertEqual(self.user.voip_pbx_user_id, 103)
        self.assertEqual(self.call_group.pbx_group_id, 106)

    def test_rejects_an_older_mapping(self):
        resources = self._resources()
        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(2, resources)
        resources["users"][0]["user_id"] = 203

        with self.assertRaisesRegex(ValidationError, "older tenant migration"):
            self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)

        self.assertEqual(self.user.voip_pbx_user_id, 103)

    def test_rejects_a_divergent_retry(self):
        resources = self._resources()
        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)
        resources["users"][0]["user_id"] = 203

        with self.assertRaisesRegex(ValidationError, "reuse an identifier"):
            self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)

        self.assertEqual(self.user.voip_pbx_user_id, 103)

    def test_applies_a_newer_mapping(self):
        resources = self._resources()
        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(1, resources)
        resources["users"][0]["user_id"] = 203

        self.env["voip.pbx.service"]._apply_tenant_migration_mapping(2, resources)

        self.assertEqual(self.user.voip_pbx_user_id, 203)

    def test_controller_passes_the_signed_migration_id_and_resources(self):
        resources = self._resources()
        envelope = {
            "client_uuid": "migration-client-uuid",
            "migration_id": 42,
            "resources": resources,
        }
        with (
            patch(f"{CONTROLLER_PATH}.request", SimpleNamespace(env=self.env)),
            patch(f"{CONTROLLER_PATH}._decode_phone_service_token", return_value=envelope),
            patch(
                "odoo.addons.voip.models.pbx_service."
                "PBXService._apply_tenant_migration_mapping",
            ) as apply_mapping,
        ):
            PhoneServiceApiController().apply_tenant_migration_mapping("signed-token")

        apply_mapping.assert_called_once_with(42, resources)

    def test_controller_rejects_a_malformed_mapping_envelope(self):
        for values in (
            {},
            {"migration_id": 0, "resources": {}},
            {"migration_id": True, "resources": {}},
            {"migration_id": 1, "resources": []},
        ):
            envelope = {"client_uuid": "migration-client-uuid", **values}
            with (
                self.subTest(values=values),
                mute_logger(CONTROLLER_PATH),
                patch(f"{CONTROLLER_PATH}.request", SimpleNamespace(env=self.env)),
                patch(f"{CONTROLLER_PATH}._decode_phone_service_token", return_value=envelope),
                self.assertRaises(Forbidden),
            ):
                PhoneServiceApiController().apply_tenant_migration_mapping("signed-token")
