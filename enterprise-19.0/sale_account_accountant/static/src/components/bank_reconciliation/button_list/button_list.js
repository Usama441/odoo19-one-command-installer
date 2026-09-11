import { BankRecButtonList } from "@account_accountant/components/bank_reconciliation/button_list/button_list";
import { _t } from "@web/core/l10n/translation";
import { patch } from "@web/core/utils/patch";

patch(BankRecButtonList, {
    props: {
        ...BankRecButtonList.props,
        availableSaleOrders: { type: Array, optional: true },
    },
    defaultProps: {
        ...BankRecButtonList.defaultProps,
        availableSaleOrders: [],
    },
});

patch(BankRecButtonList.prototype, {
    actionOpenSaleOrders() {
        const singleSale = this.props.availableSaleOrders.length === 1;
        const numberRecordsDepend = {};
        if (singleSale) {
            numberRecordsDepend.res_id = this.props.availableSaleOrders[0];
            numberRecordsDepend.views = [[false, "form"]];
        } else {
            numberRecordsDepend.views = [
                [false, "list"],
                [false, "form"],
            ];
            numberRecordsDepend.domain = [["id", "in", this.props.availableSaleOrders]];
        }

        this.action.doAction({
            type: "ir.actions.act_window",
            res_model: "sale.order",
            target: "current",
            ...numberRecordsDepend,
        });
    },

    get isSalesButtonShown() {
        return this.props.availableSaleOrders.length;
    },

    get buttons() {
        const buttonsToDisplay = super.buttons;
        if (this.isSalesButtonShown) {
            buttonsToDisplay.sale = {
                label: _t("Sales"),
                count: this.props.availableSaleOrders.length,
                action: this.actionOpenSaleOrders.bind(this),
            };
        }
        return buttonsToDisplay;
    },
});
