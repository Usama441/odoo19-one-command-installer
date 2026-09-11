import { registry } from "@web/core/registry";
import { stepUtils } from "@web_tour/tour_utils";

registry.category("web_tour.tours").add("test_ai_draft_chatter_button", {
    steps: () => [
        stepUtils.showAppsMenuItem(),
        {
            trigger: ".o_app[data-menu-xmlid='project.menu_main_pm']",
            run: "click",
        },
        {
            content: "Open the test project",
            trigger: ".o_kanban_view .o_kanban_record:contains(Test Project)",
            run: "click",
        },
        {
            content: "Open the test task",
            trigger: ".o_kanban_view .o_kanban_record:contains(Test Task)",
            run: "click",
        },
        {
            content: "Waiting for form view",
            trigger: ".o_form_view",
        },
        {
            content: "Click on the chatter's AI button",
            trigger: "button img.ai-systray-icon",
            run: "click",
        },
        {
            content: "Check that the second prompt button is correct",
            trigger: "div.o-mail-Thread button:contains('Write a followup answer')",
        },
        {
            content: "Click on the first prompt button to send the AI one of the default messages",
            trigger: "div.o-mail-Thread button:contains('Summarize the chatter conversation')",
            run: "click",
        },
        {
            content: "Check that the default message is shown",
            trigger: ".o-mail-Message-body:contains('Summarize the chatter conversation')",
        },
        {
            content: "Check that the AI gives a reply",
            trigger: ".o-mail-Message-body:has(p:contains('This is dummy ai response'))",
        },
        {
            content: "Hover over the user message so its action buttons appear",
            trigger: ".o-mail-Message:eq(1)",
            run: "hover",
        },
        {
            content: "Check that the user message has the copy button",
            trigger: ".o-mail-Message:eq(1):has(button[name='copy-message'])",
        },
        {
            content: "Check that the user message doesn't have the send message button",
            trigger: ".o-mail-Message:eq(1):not(:has(button[name='send-message-direct']))",
        },
        {
            content: "Check that the user message doesn't have the log note button",
            trigger: ".o-mail-Message:eq(1):not(:has(button[name='log-note-direct']))",
        },
        {
            content: "Hover over the AI message so its action buttons appear",
            trigger: ".o-mail-Message:eq(2)",
            run: "hover",
        },
        {
            content: "Check that the AI message has the copy button",
            trigger: ".o-mail-Message:eq(2):has(button[name='copy-message'])",
        },
        {
            content: "Check that the AI message has the send message button",
            trigger: ".o-mail-Message:eq(2):has(button[name='send-message-direct'])",
        },
        {
            content: "Check that the AI message has the log note button",
            trigger: ".o-mail-Message:eq(2):has(button[name='log-note-direct'])",
        },
        {
            content: "Hover over the AI message so the action buttons appear",
            trigger: ".o-mail-Message:eq(2)",
            run: "hover",
        },
        {
            content: "Click on the send message button",
            trigger: "button[name='send-message-direct']",
            run: "click",
        },
        {
            content: "The message composer dialog should open",
            trigger: ".o_mail_composer_form_view",
        },
        {
            content: "The AI message should be posted in the composer dialog",
            trigger: ".odoo-editor-editable:eq(1):has(p:contains('This is dummy ai response'))",
        },
        {
            content: "Close the composer dialog",
            trigger: ".btn-close",
            run: "click",
        },
        {
            content: "Hover over the AI message so the action buttons appear",
            trigger: ".o-mail-Message:eq(2)",
            run: "hover",
        },
        {
            content: "Click on the log note button",
            trigger: "button[name='log-note-direct']",
            run: "click",
        },
        {
            content: "The note composer dialog should open",
            trigger: ".o_mail_composer_form_view",
        },
        {
            content: "The AI message should be posted in the composer dialog",
            trigger: ".odoo-editor-editable:eq(1):has(p:contains('This is dummy ai response'))",
        },
        {
            content: "Click on the 'log' chatter button",
            trigger: "button:has(span:contains('Log'))",
            run: "click",
        },
        {
            content: "Check the the AI response was actually posted as a note",
            trigger: ".o-mail-Message-body:eq(0):has(p:contains('This is dummy ai response'))",
        },
    ],
});

registry.category("web_tour.tours").add("test_ai_draft_html_field", {
    steps: () => [
        stepUtils.showAppsMenuItem(),
        {
            trigger: ".o_app[data-menu-xmlid='project.menu_main_pm']",
            run: "click",
        },
        {
            content: "Open the test project",
            trigger: ".o_kanban_view .o_kanban_record:contains(Test Project)",
            run: "click",
        },
        {
            content: "Open the test task",
            trigger: ".o_kanban_view .o_kanban_record:contains(Test Task)",
            run: "click",
        },
        {
            content: "Click on the HTML editor to show power buttons",
            trigger: ".note-editable",
            run: "click",
        },
        {
            content: "Click on the ai powerbutton item",
            trigger: ".power_button.ai-logo-icon",
            run: "click",
        },
        {
            content: "Check that the chat window appears",
            trigger: ".o-mail-ChatWindow.o-isAiComposer",
        },
        {
            content: "Write a message for the AI",
            trigger: "textarea.o-mail-Composer-input",
            run: "edit Generic prompt to AI",
        },
        {
            content: "Click on the send button to send the AI the default message",
            trigger: "button[name='send-message']",
            run: "click",
        },
        {
            content: "Check that the AI gives a reply",
            trigger: ".o-mail-Message-body:has(p:contains('This is dummy ai response'))",
        },
        {
            content: "Hover over the user message so its action buttons appear",
            trigger: ".o-mail-Message:eq(1)",
            run: "hover",
        },
        {
            content: "Check that the user message has the copy button",
            trigger: ".o-mail-Message:eq(1):has(button[name='copy-message'])",
        },
        {
            content: "Check that the user message doesn't have the insert button",
            trigger: ".o-mail-Message:eq(1):not(:has(button[name='insertToComposer']))",
        },
        {
            content: "Hover over the AI message so its action buttons appear",
            trigger: ".o-mail-Message:eq(2)",
            run: "hover",
        },
        {
            content: "Check that the AI message has the copy button",
            trigger: ".o-mail-Message:eq(2):has(button[name='copy-message'])",
        },
        {
            content: "Check that the AI message has the insert button",
            trigger: ".o-mail-Message:eq(2):has(button[name='insertToComposer'])",
        },
        {
            content: "Hover over the AI message so the action button appear",
            trigger: ".o-mail-Message:eq(2)",
            run: "hover",
        },
        {
            content: "Click on the send message button",
            trigger: "button[name='insertToComposer']",
            run: "click",
        },
        {
            content: "Check the the AI response was actually inserted in the HTML field ",
            trigger: ".note-editable:has(div:contains('This is dummy ai response'))",
        },
    ],
});

registry.category("web_tour.tours").add("test_ai_ask_ai_button", {
    steps: () => [
        stepUtils.showAppsMenuItem(),
        {
            trigger: ".o_app[data-menu-xmlid='project.menu_main_pm']",
            run: "click",
        },
        {
            trigger: ".o_searchview_input",
            run: "click",
        },
        {
            trigger: ".o-dropdown-item.o_ask_ai:contains('Ask AI')",
            run: "click",
        },
        {
            trigger: ".o-mail-ChatWindow:contains('Ask AI')",
        },
    ],
});
