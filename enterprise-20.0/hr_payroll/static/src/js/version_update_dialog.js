import { Component, signal, t, useProps } from "@odoo/owl";
import { DateTimeInput } from "@web/core/datetime/datetime_input";
import { Dialog } from "@web/core/dialog/dialog";
import { deserializeDate, formatDate, serializeDate } from "@web/core/l10n/dates";

const { DateTime } = luxon;

export class VersionUpdateDialog extends Component {
    static template = "l10n_be_hr_payroll.VersionUpdateDialog";
    static components = { DateTimeInput, Dialog };

    props = useProps({
        cancel: t.function(),
        close: t.function(),
        confirm: t.function(),
        payslipsCount: t.number().optional(),
        // start of the first payslip period not paid yet, if after the current version start
        nextPeriodStart: t.or([t.string(), t.literal(false)]).optional(),
        currentVersionStart: t.or([t.string(), t.literal(false)]).optional(),
    });

    choice = signal(this.props.nextPeriodStart ? "next_period" : "specific_date");
    specificDate = signal(DateTime.now().startOf("month"));

    formatDate(date) {
        return date ? formatDate(deserializeDate(date)) : "";
    }

    get isNewVersion() {
        return this.choice() !== "current_version";
    }

    onApply = () => {
        this.props.confirm({
            dateStart:
                this.choice() === "next_period"
                    ? this.props.nextPeriodStart
                    : serializeDate(this.specificDate()),
            mode: this.isNewVersion ? "create_new_version" : "correct_current_version",
        });
        this.props.close();
    };

    onDiscard = () => {
        this.props.cancel();
        this.props.close();
    };
}
