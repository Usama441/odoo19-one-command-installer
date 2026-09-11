import { WebClient } from "@web/webclient/webclient";
import { user } from "@web/core/user";

import { describe, expect, test } from "@odoo/hoot";
import { animationFrame, waitFor } from "@odoo/hoot-dom";
import {
    contains,
    defineActions,
    defineModels,
    fields,
    getService,
    mountWithCleanup,
    onRpc,
    patchWithCleanup,
    serverState,
} from "@web/../tests/web_test_helpers";

import {
    DocumentsModels,
    getDocumentsTestServerModelsData,
    makeDocumentRecordData,
} from "@documents/../tests/helpers/data";
import { makeDocumentsMockEnv } from "@documents/../tests/helpers/model";
import { basicDocumentsKanbanArch } from "@documents/../tests/helpers/views/kanban";
import { getEnrichedSearchArch } from "@documents/../tests/helpers/views/search";

describe.current.tags("desktop");

defineModels(DocumentsModels);

defineActions([
    {
        id: 1,
        name: "Documents",
        res_model: "documents.document",
        views: [[false, "kanban"]],
    },
]);
DocumentsModels.DocumentsDocument._views = {
    kanban: basicDocumentsKanbanArch,
    [["search", false]]: getEnrichedSearchArch(),
};
DocumentsModels.DocumentsOperation._views = {
    form: `<form>
        <field name="display_name" invisible="1" force_save="1"/>
        <field name="user_permission" invisible="1" force_save="1"/>
        <field name="access_internal" invisible="1" force_save="1"/>
        <field name="access_via_link" invisible="1" force_save="1"/>
        <field name="is_access_via_link_hidden" invisible="1" force_save="1"/>
        <field name="operation" readonly="1" invisible="1"/>
        <field name="attachment_id" invisible="1" force_save="1"/>
        <sheet>
            <field
                name="destination"
                widget="documents_user_folder_id_char"
                options="{
                    'extraUpdateFields': [
                        'display_name', 'user_permission', 'access_internal', 'access_via_link', 
                        'is_access_via_link_hidden',
                    ],
                    'ulClass': 'o_documents_operation_search_panel',
                }"
            />
        </sheet>
        <footer>
            <widget name="documents_operation_confirmation"/>
            <widget name="documents_operation_new_folder"/>
            <button string="Discard" special="cancel" class="btn-secondary"/>
        </footer>
    </form>`,
};
onRpc("/documents/touch/accessTokenRequest", () => ({}));

test('Internal users can always move to "My Drive"', async function () {
    const serverData = getDocumentsTestServerModelsData([
        makeDocumentRecordData(2, "Request", { owner_id: serverState.userId }),
        makeDocumentRecordData(3, "Folder 2", { owner_id: serverState.userId, type: "folder" }),
    ]);
    serverData["documents.document"][0].user_permission = "view";
    await makeDocumentsMockEnv({ serverData });
    await mountWithCleanup(WebClient);
    await getService("action").doAction(1);

    await contains(".o_kanban_record:contains('Request') .o_record_selector").click();
    await contains(".o_dropdown_title").click();

    await contains(".o-dropdown-item .fa-sign-in").click(); // Move (not 'to Trash')
    await animationFrame();
    expect(".btn-primary:contains('Move to My Drive')").not.toHaveAttribute("disabled");
    expect(".btn-secondary:contains('Create a folder in My Drive')").toHaveCount(1);

    await contains(".modal-content li div span:contains('Folder 1')").click();
    await animationFrame();
    expect(".btn-primary:contains('Insufficient access to Folder 1')").toHaveAttribute("disabled");
    expect(".btn-secondary:contains('Create a folder in Folder 1')").toHaveCount(0);

    await contains(".modal-content li div span:contains('Folder 2')").click();
    await animationFrame();
    expect(".btn-primary:contains('Move to Folder 2')").not.toHaveAttribute("disabled");
    expect(".btn-secondary:contains('Create a folder in Folder 2')").toHaveCount(1);
});

test("Portal user without edit folder has no Move button", async function () {
    const serverData = getDocumentsTestServerModelsData([
        makeDocumentRecordData(2, "Request", { folder_id: 1, owner_id: serverState.userId }),
    ]);
    serverData["documents.document"][0].user_permission = "view";
    patchWithCleanup(user, {
        hasGroup: (group) => group === "base.group_portal",
    });
    await makeDocumentsMockEnv({ serverData });
    await mountWithCleanup(WebClient);
    await getService("action").doAction(1);

    await contains(".o_kanban_record:contains('Request') .o_record_selector").click();
    await contains(".o_dropdown_title").click();
    await waitFor(".o-dropdown-item");
    expect(".o-dropdown-item .fa-sign-in").toHaveCount(0); // Move (not 'to Trash')
});

test("Portal user with any edit folder has the Move button", async function () {
    const serverData = getDocumentsTestServerModelsData([
        makeDocumentRecordData(2, "Request", { folder_id: 1, user_permission: "edit" }),
    ]);
    serverData["documents.document"][0].user_permission = "edit";
    patchWithCleanup(user, {
        hasGroup: (group) => group === "base.group_portal",
    });
    patchWithCleanup(DocumentsModels.DocumentsOperation._fields, {
        destination: fields.Char({ default: "1" }),
        display_name: fields.Char({ default: "Folder 1" }),
    });
    await makeDocumentsMockEnv({ serverData });
    await mountWithCleanup(WebClient);
    await getService("action").doAction(1);

    await contains(".o_kanban_record:contains('Request') .o_record_selector").click();
    await contains(".o_dropdown_title").click();
    await contains(".o-dropdown-item .fa-sign-in").click(); // Move (not 'to Trash')
    await waitFor(".btn-primary:contains('Move to Folder 1')");
    expect(".btn-secondary:contains('Create a folder')").toHaveCount(0);
});
