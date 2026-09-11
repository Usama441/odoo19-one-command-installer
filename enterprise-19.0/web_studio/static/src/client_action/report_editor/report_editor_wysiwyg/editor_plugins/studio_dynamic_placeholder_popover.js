import { Component, onWillStart, useState } from "@odoo/owl";
import { useService, useAutofocus } from "@web/core/utils/hooks";
import { useHotkey } from "@web/core/hotkeys/hotkey_hook";
import { ModelFieldSelector } from "@web/core/model_field_selector/model_field_selector";
import { sortBy } from "@web/core/utils/arrays";

export class StudioDynamicPlaceholderPopover extends Component {
    static template = "web_studio.StudioDynamicPlaceholderPopover";
    static components = { ModelFieldSelector };
    static props = {
        resModel: String,
        availableQwebVariables: Object,
        close: Function,
        validate: Function,
        isEditingFooterHeader: Boolean,
        initialQwebVar: { optional: true, type: String },
        showOnlyX2ManyFields: Boolean,
        initialPath: { optional: true },
        initialLabelValue: { optional: true },
    };
    static defaultProps = {
        initialQwebVar: "",
        initialPath: false,
        initialLabelValue: false,
    };

    setup() {
        useAutofocus();
        this.state = useState({
            currentVar: this.getDefaultVariable(),
            path: this.props.initialPath || "",
            isPathSelected: false,
            labelValue: this.props.initialLabelValue || null,
        });
        this.fieldService = useService("field");
        useHotkey("Enter", () => this.validate(), { bypassEditableProtection: true });
        useHotkey("Escape", () => this.props.close(), { bypassEditableProtection: true });

        onWillStart(async () => {
            if (this.state.path) {
                const fieldInfo = (
                    await this.fieldService.loadFieldInfo(this.currentResModel, this.state.path)
                ).fieldDef;
                this.fieldType = fieldInfo.type;
                this.state.fieldName = fieldInfo.string;
            }
        });
    }

    get labelValueInput() {
        const state = this.state;
        const lv = state.labelValue;
        return (lv !== null ? lv : state.fieldName) || "";
    }
    onLabelInput(ev) {
        const val = ev.target.value;
        this.state.labelValue = val;
    }

    filter(fieldDef) {
        if (this.props.showOnlyX2ManyFields) {
            return ["one2many", "many2many"].includes(fieldDef.type);
        } else {
            /**
             * We don't want to display x2many fields inside a report as it would not make sense.
             * We also don't want to display boolean fields.
             * This override is necessary because we want to be able to select non-searchable fields.
             * There is no reason as to why this wouldn't be allowed inside a report as we don't search on those fields,
             * we simply render them.
             */
            return !["one2many", "boolean", "many2many"].includes(fieldDef.type);
        }
    }

    async validate() {
        const resModel = this.currentResModel;
        const fieldInfo = (await this.fieldService.loadFieldInfo(resModel, this.state.path))
            .fieldDef;
        if (!fieldInfo) {
            return;
        }
        const filename_exists = (
            await this.fieldService.loadFieldInfo(resModel, this.state.path + "_filename")
        ).fieldDef;
        const is_image = fieldInfo.type == "binary" && !filename_exists;
        this.props.validate(
            this.state.currentVar,
            this.state.path,
            this.labelValueInput,
            is_image,
            fieldInfo.relation,
            fieldInfo.string
        );
        this.props.close();
    }

    setPath(path, { fieldDef }) {
        this.state.path = path;
        this.state.fieldName = fieldDef?.string;
        this.fieldType = fieldDef?.type;
    }

    get currentModel() {
        const currentVar = this.state.currentVar;
        const model = currentVar && this.props.availableQwebVariables[currentVar];
        return model || {};
    }

    get currentResModel() {
        const resModel = this.currentModel.model;
        return resModel || this.props.resModel;
    }

    get sortedVariables() {
        const entries = Object.entries(this.props.availableQwebVariables).filter(
            ([k, v]) => v.in_foreach && !this.props.isEditingFooterHeader
        );
        const resModel = this.props.resModel;
        const sortFn = ([k, v]) => {
            let score = 0;
            if (k === "doc") {
                score += 2;
            }
            if (k === "docs") {
                score -= 2;
            }
            if (k === "o") {
                score++;
            }
            if (v.model === resModel) {
                score++;
            }
            return score;
        };

        const mapFn = ([k, v]) => ({
            value: k,
            label: `${k} (${v.name})`,
        });
        return sortBy(entries, sortFn, "desc").map((e) => mapFn(e));
    }

    getDefaultVariable() {
        const initialQwebVar = this.props.initialQwebVar;
        if (initialQwebVar && initialQwebVar in this.props.availableQwebVariables) {
            return initialQwebVar;
        }
        if (this.props.isEditingFooterHeader) {
            const companyVar = Object.entries(this.props.availableQwebVariables).find(
                ([k, v]) => v.model === "res.company"
            );
            return companyVar && companyVar[0];
        }

        let defaultVar = this.sortedVariables.find((v) => ["doc", "o"].includes(v.value));
        defaultVar =
            defaultVar ||
            this.sortedVariables.find(
                (v) => this.props.availableQwebVariables[v.value].model === this.props.resModel
            );
        return defaultVar && defaultVar.value;
    }
}
