import { describe, test } from "@odoo/hoot";
import { click, contains, openDiscuss, start, startServer } from "@mail/../tests/mail_test_helpers";
import { Command, serverState } from "@web/../tests/web_test_helpers";
import { defineWhatsAppModels } from "./whatsapp_test_helpers";

describe.current.tags("desktop");
defineWhatsAppModels();

test("message translation in whatsapp", async () => {
    const pyEnv = await startServer();
    const channelId = pyEnv["discuss.channel"].create({
        name: "WhatsApp 1",
        channel_type: "whatsapp",
        channel_member_ids: [
            Command.create({ partner_id: serverState.partnerId }),
            Command.create({ partner_id: serverState.publicPartnerId }),
        ],
    });
    pyEnv["mail.message"].create({
        body: "Laisse-moi manger tranquillement ma pizza avec ananas!",
        model: "discuss.channel",
        res_id: channelId,
    });
    await start();
    await openDiscuss(channelId);
    await contains(".o-mail-Message");
    await click("[title='Expand']");
    await contains(".o-dropdown-item:contains('Translate')");
});
