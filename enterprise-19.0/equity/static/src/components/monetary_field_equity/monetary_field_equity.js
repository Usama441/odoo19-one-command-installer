import { formatMonetary } from "@web/views/fields/formatters";
import { monetaryField, MonetaryField } from "@web/views/fields/monetary/monetary_field";
import { registry } from "@web/core/registry";

export class MonetaryFieldEquity extends MonetaryField {
    static props = {
        ...MonetaryField.props,
        humanReadable: { type: Boolean, optional: true },
    };

    /** Override **/
    get formattedValue() {
        if (this.props.inputType === "number" && !this.props.readonly && this.value) {
            return this.value;
        }
        return formatMonetary(this.value, {
            digits: this.currencyDigits,
            currencyId: this.currencyId,
            noSymbol: !this.props.readonly || this.props.hideSymbol,
            trailingZeros: this.props.trailingZeros,
            humanReadable: this.props.humanReadable,
        });
    }

    onInput(ev) {
        if (!isNaN(ev.target.value)) {
            ev.target.value = Math.abs(ev.target.value);
        }
        super.onInput(ev);
    }
}

export const monetaryFieldEquity = {
    ...monetaryField,
    component: MonetaryFieldEquity,
    extractProps({ options }) {
        return {
            ...monetaryField.extractProps(...arguments),
            humanReadable: options.human_readable,
        };
    },
};

registry.category("fields").add("monetary_equity", monetaryFieldEquity);
