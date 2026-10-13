import { defineMailModels } from "@mail/../tests/mail_test_helpers";
import { describe, expect, test } from "@odoo/hoot";
import { setInputFiles } from "@odoo/hoot-dom";
import { animationFrame } from "@odoo/hoot-mock";
import { contains, mountWithCleanup, onRpc } from "@web/../tests/web_test_helpers";
import { IconCreator } from "@web_studio/client_action/icon_creator/icon_creator";

describe.current.tags("desktop");

const sampleIconUrl = "/web/Parent.src/img/default_icon_app.png";

defineMailModels();

test("icon creator: with initial web icon data", async () => {
    expect.assertions(4);

    await mountWithCleanup(IconCreator, {
        props: {
            editable: true,
            type: "base64",
            webIconData: sampleIconUrl,
            onIconChange(icon) {
                expect.step("icon-changed");
                expect(icon).toEqual({
                    backgroundColor: "#FFFFFF",
                    color: "#00CEB3",
                    icon: "home",
                    type: "custom_icon",
                });
            },
        },
    });
    await animationFrame();

    expect(".o_web_studio_uploaded_image").toHaveStyle({
        backgroundImage: new RegExp(sampleIconUrl),
    });

    await contains(".o_web_studio_upload a").click();

    expect.verifySteps(["icon-changed"]);
    expect(".o_web_studio_upload input").toHaveAttribute("accept", "image/png");
});

test("icon creator: without initial web icon data", async () => {
    await mountWithCleanup(IconCreator, {
        props: {
            backgroundColor: "rgb(255, 0, 128)",
            color: "rgb(0, 255, 0)",
            editable: false,
            icon: "favorite",
            type: "custom_icon",
            onIconChange: () => {},
        },
    });

    expect(".o_app_icon").toHaveStyle({
        backgroundColor: "rgb(255, 0, 128)",
    });

    expect(".o_app_icon i").toHaveStyle({
        color: "rgb(0, 255, 0)",
    });

    expect(".o_app_icon i").toHaveAttribute("data-icon", "favorite");
});

test("icon creator: select an outlined and a filled icon", async () => {
    await mountWithCleanup(IconCreator, {
        props: {
            backgroundColor: "#FFFFFF",
            color: "#00CEB3",
            editable: true,
            icon: "home",
            type: "custom_icon",
            onIconChange({ icon }) {
                expect.step(icon);
            },
        },
    });

    await contains(".o_web_studio_selector_icon").click();
    expect(".font-icons-icon:not(.oi-filled)[data-icon='home']").toHaveClass(
        "o_we_attachment_selected"
    );

    await contains(".font-icons-icon.oi-filled[data-icon='favorite']").click();
    expect.verifySteps(["favorite_f"]);
    expect(".o_web_studio_selector_icon_menu").toHaveCount(0);

    await contains(".o_web_studio_selector_icon").click();
    await contains(".font-icons-icon:not(.oi-filled)[data-icon='favorite']").click();
    expect.verifySteps(["favorite"]);
});

test("icon creator: upload image for icon", async () => {
    const PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
    const PNG_BYTES = Uint8Array.from(atob(PNG_B64), (c) => c.charCodeAt(0));

    onRpc("/web/binary/upload_attachment", () => [{ id: 1, filename: "icon.png" }]);

    onRpc("ir.attachment", "read", () => [
        { id: 1, raw: { filename: "icon.png", content: PNG_B64, size: PNG_BYTES.length } },
    ]);

    await mountWithCleanup(IconCreator, {
        props: {
            editable: true,
            type: "custom_icon",
            onIconChange: () => expect.step("icon-changed"),
        },
    });

    await contains(".o_web_studio_upload .o_input_file", { visible: false }).click();
    await setInputFiles([new File([PNG_BYTES], "icon.png", { type: "image/png" })]);

    await expect.waitForSteps(["icon-changed"]);
});
