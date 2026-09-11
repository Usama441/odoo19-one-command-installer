import { registry } from "@web/core/registry";
import { Dropdown } from "@web/core/dropdown/dropdown";
import { Component, onWillStart } from "@odoo/owl";
import { standardFieldProps } from "@web/views/fields/standard_field_props";
import { DropdownItem } from "@web/core/dropdown/dropdown_item";
import { cookie } from "@web/core/browser/cookie";
import { user } from "@web/core/user";

export class AccountReturnSelectionBadge extends Component {
    static template = "account_reports.AccountReturnSelectionBadgeField";
    static props = {
        ...standardFieldProps,
        decorations: { type: Object, optional: true },
        options: { type: Object, optional: true },
        class: { type: String, optional: true },
        size: { type: String, optional: true },
    };

    setup() {
        onWillStart(async () => {
            this.editableOptions = await this.getEditableOptions();
        });
    }

    static defaultProps = {
        size: "normal"
    };

    static components = {
        Dropdown,
        DropdownItem,
    }

    get options() {
        return this.props.record.fields[this.props.name].selection;
    }

    get value() {
        return this.props.record.data[this.props.name];
    }

    get required() {
        return this.props.record.fields[this.props.name].required;
    }

    get display() {
        const result = this.options.filter((val) => val[0] == this.value)[0];
        if(result) {
            return result[1];
        }
        return null;
    }

    async getEditableOptions () {
        const editableOptions = [false]

        for (let [key, value] of Object.entries(this.props.options)) {
            if ([true, undefined].includes(value.can_edit) || typeof value.can_edit == 'string' && await user.hasGroup(value.can_edit)) {
                editableOptions.push(key);
            }
        }

        return editableOptions;
    }

    decorationForValue(value, isDropdownItem=false) {
        const colorScheme = cookie.get("color_scheme");
        const defaultStyle = isDropdownItem && colorScheme == 'dark' ? "text-bg-200" : "text-bg-300";
        const decoration = this.props.options[value]?.decoration;
        if (decoration) {
            if (decoration === "muted") {
                return defaultStyle;
            }
            return `text-bg-${this.props.options[value].decoration}`;
        }
        return isDropdownItem && colorScheme == 'dark' ? "text-bg-200" : "text-bg-100";
    }

    get additionalClassName() {
        return this.props.class || "";
    }

    get capsuleStyle() {
        if (this.props.size === 'normal') {
            return "min-width: 70px; height:21px;";
        }
        else {
            return "";
        }
    }

    async onChange(value) {
        await this.props.record.update(
            { [this.props.name]: value },
            { save: true }
        );
        this.env.reload?.()
    }
}

export const accountReturnSelectionBadge = {
    supportedTypes: ["selection"],
    component: AccountReturnSelectionBadge,
    extractProps: ({options}) => {
        return { options };
    },
}

registry.category("fields").add("account_return_selection_badge", accountReturnSelectionBadge)
