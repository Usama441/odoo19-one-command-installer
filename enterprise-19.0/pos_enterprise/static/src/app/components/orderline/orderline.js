import { Component } from "@odoo/owl";
import { usePrepDisplay } from "@pos_enterprise/app/services/preparation_display_service";
import { useService } from "@web/core/utils/hooks";
import { TagsList } from "@web/core/tags_list/tags_list";
import { useDelayedValueChange } from "@pos_enterprise/app/utils/utils";

export class Orderline extends Component {
    static components = { TagsList };
    static template = "pos_enterprise.Orderline";
    static props = {
        orderline: Object,
    };

    setup() {
        this.prepDisplay = usePrepDisplay();
        this.orm = useService("orm");
        this.noteState = useDelayedValueChange(() => this.preparation_line.internal_note);
    }

    get preparation_line() {
        return this.props.orderline.prep_line_id;
    }

    get attributeData() {
        return Object.values(
            this.preparation_line.attribute_value_ids.reduce((acc, attr) => {
                if (acc[attr.attribute_id.id]) {
                    acc[attr.attribute_id.id].value += `, ${attr.name}`;
                } else {
                    acc[attr.attribute_id.id] = {
                        id: attr,
                        name: attr.attribute_id.name,
                        value: attr.name,
                    };
                }

                return acc;
            }, {})
        );
    }
    get internalNotes() {
        return JSON.parse(this.preparation_line.internal_note || "[]");
    }
    get customerNotes() {
        return (this.preparation_line.customer_note || "").split("\n").filter((note) => note);
    }
}
