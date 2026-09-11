import { components } from "@odoo/o-spreadsheet";
import { ODOO_AGGREGATORS } from "@spreadsheet/pivot/pivot_helpers";
import { ModelFieldSelector } from "@web/core/model_field_selector/model_field_selector";
import { ModelFieldSelectorPopover } from "@web/core/model_field_selector/model_field_selector_popover";
const { PivotLayoutConfigurator } = components;

/**
 * This override prevents following relations for many2many fields.
 */
export class PivotModelFieldSelectorPopover extends ModelFieldSelectorPopover {
    canFollowRelationFor(fieldDef) {
        if (fieldDef.type === "many2many" || !fieldDef.store) {
            return false;
        }
        return super.canFollowRelationFor(fieldDef);
    }
}

export class PivotModelFieldSelector extends ModelFieldSelector {
    static template = "spreadsheet_edition.PivotModelFieldSelector";
    static components = {
        Popover: PivotModelFieldSelectorPopover,
    };
}

export class OdooPivotLayoutConfigurator extends PivotLayoutConfigurator {
    static template = "spreadsheet_edition.OdooPivotLayoutConfigurator";
    static components = {
        ...PivotLayoutConfigurator.components,
        PivotModelFieldSelector,
    };

    setup() {
        super.setup(...arguments);
        this.AGGREGATORS = ODOO_AGGREGATORS;
    }

    get allDimensions() {
        return this.props.definition.rows.concat(this.props.definition.columns);
    }

    addColumnDimension(fieldName) {
        if (this.allDimensions.some((f) => f.fieldName === fieldName)) {
            return;
        }
        super.addColumnDimension(fieldName);
    }

    addRowDimension(fieldName) {
        if (this.allDimensions.some((f) => f.fieldName === fieldName)) {
            return;
        }
        super.addRowDimension(fieldName);
    }

    filterGroupableFields(field, path) {
        const fullField = path ? `${path}.${field.name}` : field.name;
        if (this.allDimensions.some((f) => f.fieldName === fullField)) {
            return false;
        }
        return field.groupable;
    }
}
