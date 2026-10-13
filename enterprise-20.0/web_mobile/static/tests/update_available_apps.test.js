import { beforeEach, expect, test } from "@odoo/hoot";
import { waitFor, waitForNone } from "@odoo/hoot-dom";
import { Component, useProps, xml } from "@odoo/owl";
import {
    defineMenus,
    getService,
    mountWithCleanup,
    patchWithCleanup,
} from "@web/../tests/web_test_helpers";
import { registry } from "@web/core/registry";
import { user } from "@web/core/user";
import { WebClientEnterprise } from "@web_enterprise/webclient/webclient";

import mobile from "@web_mobile/js/services/core";

const PNG_BASE64 = "iVBORw0KGgo=";

class TestClientAction extends Component {
    static template = xml`<div class="test_client_action"/>`;
    props = useProps();
}

defineMenus([
    { id: 0 }, // prevents auto-loading the first action
    {
        id: 1,
        name: "Png App",
        appID: 1,
        actionID: 1001,
        actionPath: "png-app",
        xmlid: "menu_png",
        webIconData: `data:image/png;base64,${PNG_BASE64}`,
    },
    {
        id: 2,
        name: "Svg App",
        appID: 2,
        actionID: 1002,
        xmlid: "menu_svg",
        webIconData: "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=",
    },
    {
        id: 3,
        name: "Font Icon App",
        appID: 3,
        actionID: 1003,
        xmlid: "menu_font_icon",
        webIcon: "fa-cog,#FFFFFF,#000000",
    },
    {
        id: 4,
        name: "Default Icon App",
        appID: 4,
        actionID: 1004,
        xmlid: "menu_default_icon",
    },
]);

const EXPECTED_APPS = [
    {
        xmlid: "menu_png",
        link: "/odoo/png-app",
        name: "Png App",
        pngIcon: PNG_BASE64,
    },
    {
        xmlid: "menu_svg",
        link: "/odoo/action-1002",
        name: "Svg App",
        pngIcon: null,
    },
    {
        xmlid: "menu_font_icon",
        link: "/odoo/action-1003",
        name: "Font Icon App",
        pngIcon: null,
    },
    {
        xmlid: "menu_default_icon",
        link: "/odoo/action-1004",
        name: "Default Icon App",
        pngIcon: null,
    },
];

beforeEach(() => {
    registry.category("actions").add("__test__client__action__", TestClientAction);
    patchWithCleanup(mobile.methods, {
        updateAvailableApps: (apps) => expect.step(apps),
    });
});

async function leaveAndReopenHomeMenu() {
    await getService("action").doAction({
        type: "ir.actions.client",
        tag: "__test__client__action__",
    });
    await waitForNone(".o_home_menu");
    await getService("home_menu").toggle(true);
    await waitFor(".o_home_menu");
}

test("available apps are sent to the native app when the home menu is displayed", async () => {
    await mountWithCleanup(WebClientEnterprise);
    await waitFor(".o_home_menu");
    expect.verifySteps([EXPECTED_APPS]);
});

test("unchanged apps are not sent again when the home menu is reopened", async () => {
    await mountWithCleanup(WebClientEnterprise);
    await waitFor(".o_home_menu");
    expect.verifySteps([EXPECTED_APPS]);

    await leaveAndReopenHomeMenu();
    expect.verifySteps([]);
});

test("reordered apps are sent again when the home menu is reopened", async () => {
    await mountWithCleanup(WebClientEnterprise);
    await waitFor(".o_home_menu");
    expect.verifySteps([EXPECTED_APPS]);

    patchWithCleanup(user, {
        get settings() {
            return {
                id: 1,
                homemenu_config: JSON.stringify(EXPECTED_APPS.map((app) => app.xmlid).reverse()),
            };
        },
    });
    await leaveAndReopenHomeMenu();
    expect.verifySteps([[...EXPECTED_APPS].reverse()]);
});
