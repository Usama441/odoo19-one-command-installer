import { browser } from "@web/core/browser/browser";
import { ListRenderer } from "@web/views/list/list_renderer";
import { PayslipActionHelper } from "../../components/payslip_action_helper/payslip_action_helper";

export class PayslipListRenderer extends ListRenderer {
    static template = "hr_payroll.PayslipListRenderer";
    static components = {
        ...ListRenderer.components,
        PayslipActionHelper,
    };
    static props = [
        ...ListRenderer.props,
        "onGenerate",
        "payRunInfo",
    ];

    setup() {
        super.setup();
        const renderer = this;
        this.rawOptionalActiveFields = {
            payrun: {},
            base: this.optionalActiveFields,
        }
        this.optionalFieldsHandler = {
            targetProp(field) {
                return (renderer.inPayrun && renderer.isPayrunOptional(field)) ? 'payrun' : 'base';
            },
            get(target, field, receiver) {
                if (field in target) {  // categories (base, payrun...)
                    return Reflect.get(target, field, receiver);
                }
                return Reflect.get(target[this.targetProp(field)], field, receiver);
            },
            set(target, field, value) {
                if (field in target) {  // categories (base, payrun...)
                    return Reflect.set(target, field, value);
                }
                return Reflect.set(target[this.targetProp(field)], field, value);
            },
        };
        this.optionalActiveFields = new Proxy(this.rawOptionalActiveFields, this.optionalFieldsHandler)
        this.keyPayrunOptionalFields = `payrun_${this.keyOptionalFields}`;
    }

    get payslipActionHelperProps() {
        const helperProps = {
            onClickCreate: this.props.onAdd.bind(this.onClickCreate),
            onClickGenerate: this.props.onGenerate.bind(this.onGenerate),
        };
        if (this.props.payRunInfo.id) {
            helperProps.payrunId = this.props.payRunInfo.id;
        }
        return helperProps;
    }

    /** utils **/
    get inPayrun() {
        return this.props?.payRunInfo?.id;
    }

    isPayrunOptional(fieldName) {
        return this.allColumns
            .filter((col) => col?.options?.payrun_optional)
            .map(col => col.name)
            .includes(fieldName)
    }

    /** overrides **/
    /**
     * @override
     */
    getActiveColumns(list) {
        if (this.inPayrun) {
            this.allColumns = this.allColumns.map((col) => (
                col.options && 'payrun_optional' in col.options
                    ? {...col, optional: col.options.payrun_optional}
                    : col
            ));
        }
        return super.getActiveColumns(list);
    }

    saveOptionalActiveFields() {
        for (const [storageKey, optionalFieldType] of [
            [this.keyOptionalFields, 'base'],
            [this.keyPayrunOptionalFields, 'payrun']
        ]) {
            let activeFields = this.rawOptionalActiveFields[optionalFieldType]
            browser.localStorage.setItem(
                storageKey,
                Object.keys(activeFields).filter(field => (activeFields[field])),
            );
        }
    }

    computeOptionalActiveFields() {
        const getOptional = (col => col.optional);
        const getPayrunOptional = (col => col.options?.payrun_optional);
        const rawOptionalActiveFields = {};
        for (const [storageKey, optionalCheck, optionalFieldType] of [
            [this.keyOptionalFields, getOptional, 'base'],
            [this.keyPayrunOptionalFields, getPayrunOptional, 'payrun'],
        ]) {
            let storage = browser.localStorage.getItem(storageKey)?.split(",");
            rawOptionalActiveFields[optionalFieldType] = Object.fromEntries(
                this.allColumns.filter(
                    col => col.type === 'field' && optionalCheck(col)
                ).map(col => [
                    col.name,
                    storage ? storage.includes(col.name) : optionalCheck(col) === 'show'
                ])
            );
        }
        return new Proxy(rawOptionalActiveFields, this.optionalFieldsHandler);
    }
}
