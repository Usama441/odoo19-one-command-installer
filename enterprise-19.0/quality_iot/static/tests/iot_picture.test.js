import { expect, test } from "@odoo/hoot";
import {
    contains,
    defineModels,
    fields,
    models,
    mountView,
} from "@web/../tests/web_test_helpers";
import { mailModels } from "@mail/../tests/mail_test_helpers";

const MY_IMAGE =
    "iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==";

class Partner extends models.Model {
    name = fields.Char();
    document = fields.Binary();

    _records = [
        { id: 1, name: "first record", document: MY_IMAGE },
    ];
}

class IotChannel extends models.Model {
    get_iot_channel() {}
}

defineModels({ Partner, IotChannel, ...mailModels });

test("Open a preview when clicked", async () => {
    await mountView({
        type: "form",
        resModel: "partner",
        resId: 1,
        arch: `
            <form>
                <field name="document" widget="iot_picture" options="{'size': [90, 90]}"/>
            </form>
        `,
    });

    expect(".o_field_iot_picture[name='document']").toHaveCount(1);
    expect(".o_field_iot_picture #picture_button button").toHaveText("Take a Picture");
    await contains(".o_field_iot_picture img").click();
    expect(".o_dialog").toHaveCount(1);
    expect(".o_viewer_img_wrapper img").toHaveAttribute("data-src", `data:image/png;base64,${MY_IMAGE}`);
    await contains(".modal-footer button").click();
    await contains(".o_field_iot_picture button:not(#picture_button button)").click();
    expect(".o_dialog").toHaveCount(0);
    expect(".o_field_iot_picture img").toHaveAttribute("data-src", "/web/static/img/placeholder.png");
});
