import OrderPaymentValidation from "@point_of_sale/app/utils/order_payment_validation";
import { patch } from "@web/core/utils/patch";
import { _t } from "@web/core/l10n/translation";

patch(OrderPaymentValidation.prototype, {
    //@override
    async validateOrder(isForceValidate) {
        if (this.pos.isCountryGermanyAndFiskaly() && !this.pos.data.network.offline) {
            if (this.pos.validateOrderFree) {
                this.pos.validateOrderFree = false;
                try {
                    await super.validateOrder(...arguments);
                } finally {
                    this.pos.validateOrderFree = true;
                }
            }
        } else {
            await super.validateOrder(...arguments);
        }
    },
    //@override
    async finalizeValidation() {
        if (this.pos.isCountryGermanyAndFiskaly() && !this.pos.data.network.offline) {
            if (this.order.isTransactionInactive()) {
                try {
                    await this.pos.createTransaction(this.order);
                } catch (error) {
                    if (error.status === 0) {
                        this.pos.showFiskalyNoInternetConfirmPopup(this);
                    } else {
                        const message = {
                            unknown: _t("An unknown error has occurred! Please, contact Odoo."),
                        };
                        this.pos.fiskalyError(error, message);
                    }
                }
            }
            if (this.order.isTransactionStarted()) {
                try {
                    await this.pos.finishShortTransaction(this.order);
                    await super.finalizeValidation(...arguments);
                } catch (error) {
                    if (error.status === 0) {
                        this.pos.showFiskalyNoInternetConfirmPopup(this);
                    } else {
                        const message = {
                            unknown: _t("An unknown error has occurred! Please, contact Odoo."),
                        };
                        this.pos.fiskalyError(error, message);
                    }
                }
            } else if (this.order.isTransactionFinished()) {
                await super.finalizeValidation(...arguments);
            }
        } else {
            await super.finalizeValidation(...arguments);
        }
    },
});
