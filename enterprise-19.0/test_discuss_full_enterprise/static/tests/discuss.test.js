import {
    click,
    contains,
    focus,
    insertText,
    openDiscuss,
    start,
    startServer,
} from "@mail/../tests/mail_test_helpers";

import { defineHrModels } from "@hr/../tests/hr_test_helpers";

import { expectElementCount } from "@html_editor/../tests/_helpers/ui_expectations";
import { insertText as htmlInsertText } from "@html_editor/../tests/_helpers/user_actions";

import { getService } from "@web/../tests/web_test_helpers";

import { describe, test } from "@odoo/hoot";
import { animationFrame } from "@odoo/hoot-mock";

describe.current.tags("desktop");
defineHrModels();

test("[text composer] Can use channel command /who", async () => {
    const pyEnv = await startServer();
    const channelId = pyEnv["discuss.channel"].create({
        channel_type: "channel",
        name: "my-channel",
    });
    await start();
    await openDiscuss(channelId);
    await insertText(".o-mail-Composer-input", "/who");
    await click(".o-mail-Composer button[title='Send']:enabled");
    await contains(".o_mail_notification", { text: "You are alone in this channel." });
});

test.tags("html composer");
test("Can use channel command /who", async () => {
    const pyEnv = await startServer();
    const channelId = pyEnv["discuss.channel"].create({
        channel_type: "channel",
        name: "my-channel",
    });
    await start();
    const composerService = getService("mail.composer");
    composerService.setHtmlComposer();
    await openDiscuss(channelId);
    await focus(".o-mail-Composer-html.odoo-editor-editable");
    const editor = {
        document,
        editable: document.querySelector(".o-mail-Composer-html.odoo-editor-editable"),
    };
    await htmlInsertText(editor, "/who");
    await click(".o-mail-Composer button[title='Send']:enabled");
    await contains(".o_mail_notification", { text: "You are alone in this channel." });
});

test("can handle command and disable mentions in AI composer", async () => {
    const pyEnv = await startServer();
    const channelId = pyEnv["discuss.channel"].create({
        channel_type: "ai_composer",
        name: "my-ai-composer",
    });
    pyEnv["discuss.channel"].create({ name: "my-channel" });
    await start();
    await openDiscuss(channelId);
    await insertText(".o-mail-Composer-input", "/help");
    await click(".o-mail-Composer button[title='Send']:enabled");
    await contains(".o-mail-Message");
    await insertText(".o-mail-Composer-input", "@");
    await animationFrame();
    await expectElementCount(".o-mail-NavigableList-item", 0);
    await insertText(".o-mail-Composer-input", "#", { replace: true });
    await expectElementCount(".o-mail-NavigableList-item", 0);
});
