from odoo.tests import tagged, HttpCase
from unittest.mock import patch


@tagged('post_install', '-at_install')
class TestAIDraftUI(HttpCase):
    @classmethod
    def _dummy_ai_submit_to_model(cls, prompt, chat_history=None, extra_system_context=""):
        return ["This is dummy ai response"]

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        project = cls.env['project.project'].create({
            'name': 'Test Project',
        })
        stage = cls.env['project.task.type'].create([{
            'name': 'Test Stage',
            'project_ids': project.ids,
        }])
        cls.env['project.task'].create({
            'name': 'Test task',
            'project_id': project.id,
            'stage_id': stage.id,
        })
        cls.env.ref('base.user_admin').write({
            'email': 'mitchell.admin@example.com'
        })

    def test_ai_draft_chatter_button(self):
        with patch.object(self.env.registry['ai.agent'], '_generate_response', self._dummy_ai_submit_to_model):
            self.start_tour("/odoo", 'test_ai_draft_chatter_button', login='admin')

    def test_ai_draft_html_field(self):
        with patch.object(self.env.registry['ai.agent'], '_generate_response', self._dummy_ai_submit_to_model):
            self.start_tour("/odoo", 'test_ai_draft_html_field', login='admin')

    def test_ai_ask_ai_button(self):
        with patch.object(self.env.registry['ai.agent'], '_generate_response', self._dummy_ai_submit_to_model):
            self.start_tour("/odoo", 'test_ai_ask_ai_button', login='admin')
