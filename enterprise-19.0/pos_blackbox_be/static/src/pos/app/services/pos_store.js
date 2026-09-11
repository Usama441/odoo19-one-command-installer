import { PosStore } from "@point_of_sale/app/services/pos_store";
import { patch } from "@web/core/utils/patch";
import { AlertDialog } from "@web/core/confirmation_dialog/confirmation_dialog";
import { _t } from "@web/core/l10n/translation";
import { NumberPopup } from "@point_of_sale/app/components/popups/number_popup/number_popup";
import { BlackboxError } from "@pos_blackbox_be/pos/app/utils/blackbox_error";

patch(PosStore.prototype, {
    async setup() {
        await super.setup(...arguments);
        this.multiple_discount = false;
    },
    async initServerData() {
        await super.initServerData();
        if (this.useBlackBoxBe()) {
            this.data.connectWebSocket("CLOCKING", (payload) => {
                if (payload.session_id == this.session.id) {
                    this.models.connectNewData(payload.data);
                }
            });
        }
    },
    async setUserSessionStatus(user, status, all = false) {
        if (!user) {
            return;
        }
        await this.data.call("pos.session", "set_user_session_work_status", [this.session.id], {
            user_id: user.id,
            status: status,
            all_insz: all,
        });
    },
    get userSessionStatus() {
        const cashier_id = this.getCashier().id;
        return this.config.module_pos_hr
            ? this.session._employees_clocked_ids.includes(cashier_id)
            : this.session._users_clocked_ids.includes(cashier_id);
    },
    //#region User Clocking
    async clock(clock_in = true, inszs = []) {
        await this.clockEmployee(this.getCashier(), clock_in, inszs);
    },
    async clockEmployee(employee, clock_in = true, inszs = []) {
        const automaticClock = Boolean(Object.keys(inszs).length > 0);
        if (Object.keys(inszs).length === 0) {
            inszs[employee.id] = this.config.module_pos_hr
                ? this.session._employee_insz_or_bis_number[employee.id]
                : this.user.insz_or_bis_number;
        }
        if (!this.clock_disabled) {
            try {
                this.clock_disabled = true;
                for (const insz of Object.entries(inszs)) {
                    const order = await this.createOrderForClocking(insz, clock_in);
                    await this.printReceipt({ order });
                    this.removeClockOrder(order);
                }
                await this.setUserSessionStatus(employee, clock_in, automaticClock);
            } finally {
                this.clock_disabled = false;
            }
        }
        this.removeEmptyOrders();
    },
    async createOrderForClocking(insz, status) {
        const order = this.addNewOrder();
        this.addLineToOrder(
            {
                product_tmpl_id: status
                    ? this.config.work_in_product.product_tmpl_id
                    : this.config.work_out_product.product_tmpl_id,
            },
            order,
            {},
            false
        );
        try {
            order.uiState.clock = status ? "in" : "out";
            order.uiState.insz = insz;
            if (this.config.module_pos_hr) {
                order.employee_id = insz[0];
            } else {
                order.user_id = insz[0];
            }
            order.state = "paid";
            const result = await this.syncAllOrders({ throw: true, orders: [order] });
            return result[0];
        } catch (error) {
            const order = this.getOrder();
            this.removeClockOrder(order);
            throw error;
        }
    },
    removeClockOrder(order) {
        this.removeOrder(order, false);
        this.selectedOrderUuid = null;
        const screen = this.defaultPage;
        this.navigate(screen.page, screen.params);
    },
    removeEmptyOrders() {
        const orders = this.models["pos.order"].filter((o) => !o.finalized);
        for (const order of orders) {
            if (order.isEmpty()) {
                this.removeOrder(order, false);
            }
        }
    },
    //#region Override
    get printOptions() {
        const res = super.printOptions;
        if (this.useBlackBoxBe()) {
            return Object.assign(res, { blackboxPrint: true });
        }
        return res;
    },
    async addLineToCurrentOrder(vals, opt = {}, configure = true) {
        const product = vals.product_tmpl_id;
        const order = this.getOrder();
        if (!vals.qty) {
            vals.qty = order.preset_id?.is_return ? -1 : 1;
        }
        if (this.useBlackBoxBe()) {
            if (product.taxes_id.length === 0 && !product.isCombo()) {
                this.dialog.add(AlertDialog, {
                    title: _t("POS error"),
                    body: _t("Product has no tax associated with it."),
                });
                return;
            } else if (
                !this.userSessionStatus &&
                product !== this.config.work_in_product.product_tmpl_id &&
                !opt.force
            ) {
                this.dialog.add(AlertDialog, {
                    title: _t("POS error"),
                    body: _t(
                        "The government's Fiscal Data Module requires every user to Clock In before " +
                            "sending an order.\n" +
                            "You can Clock In from the top-right menu (\u2261)."
                    ),
                });
                return;
            } else if (!product.taxes_id.every((tax) => tax?.tax_group_id.pos_receipt_label)) {
                this.dialog.add(AlertDialog, {
                    title: _t("POS error"),
                    body: _t(
                        "Product has no tax receipt label. Please add one on the tax group of the tax (A, B, C or D)."
                    ),
                });
                return;
            } else if (
                [
                    this.config.work_in_product.product_tmpl_id.id,
                    this.config.work_out_product.product_tmpl_id.id,
                ].includes(product.id) &&
                !opt.force
            ) {
                this.dialog.add(AlertDialog, {
                    title: _t("POS error"),
                    body: _t("This product is not allowed to be sold"),
                });
                return;
            }
        }

        return await super.addLineToCurrentOrder(vals, opt, configure);
    },
    async processServerData(loadedData) {
        await super.processServerData(loadedData);

        this.config.work_in_product = this.models["product.product"].get(
            this.config._product_product_work_in
        );
        this.config.work_out_product = this.models["product.product"].get(
            this.config._product_product_work_out
        );
    },
    disallowLineQuantityChange() {
        return this.useBlackBoxBe() || super.disallowLineQuantityChange();
    },
    restrictLineDiscountChange() {
        return this.useBlackBoxBe() || super.restrictLineDiscountChange();
    },
    restrictLinePriceChange() {
        return this.useBlackBoxBe() || super.restrictLinePriceChange();
    },
    async preSyncAllOrders(orders) {
        if (this.useBlackBoxBe() && orders.length > 0) {
            for (const order of orders) {
                const serialized = order.serializeForORM({ keepCommands: true });
                if (serialized.lines.length === 0 && serialized.state === "draft") {
                    continue;
                }
                order.uiState.receipt_type = false;
                const result = await this.pushOrderToBlackbox(order);
                if (!result) {
                    order.state = "draft";
                    throw new Error(_t("Error pushing order to blackbox"));
                }
                order.setDataForPushOrderFromBlackbox(result);
                await this.createLog(order);
            }
        }
        return super.preSyncAllOrders(orders);
    },
    async increaseCashboxOpeningCounter() {
        await this.data.call("pos.session", "increase_cash_box_opening_counter", [this.session.id]);
    },
    async increaseCorrectionCounter(amount) {
        await this.data.call("pos.session", "increase_correction_counter", [
            this.session.id,
            amount,
        ]);
    },
    async transferOrder(orderUuid, destinationTable = null, destinationOrder = null) {
        const order = this.models["pos.order"].find((o) => o.uuid === orderUuid);
        if (this.useBlackBoxBe() && order && typeof order.id === "number") {
            await this.pushCorrection(order);
        }
        await super.transferOrder(orderUuid, destinationTable, destinationOrder);
        if (this.useBlackBoxBe()) {
            await this.pushProFormaOrderLog(this.getOrder());
        }
    },
    async setDiscountFromUI(line, discount) {
        if (
            this.useBlackBoxBe() &&
            this.getOrder() &&
            typeof line.discount === "number" &&
            discount !== line.getDiscountStr() &&
            !this.multiple_discount
        ) {
            const selectedNumpadMode = this.numpadMode;
            const order = this.getOrder();
            await this.pushCorrection(order, [line]);
            const res = await super.setDiscountFromUI(...arguments);
            this.addPendingOrder([order.id]);
            await this.syncAllOrders({ throw: true });
            this.numpadMode = selectedNumpadMode;
            return res;
        } else {
            return await super.setDiscountFromUI(...arguments);
        }
    },
    async _onBeforeDeleteOrder(order) {
        if (this.useBlackBoxBe() && !order.isEmpty()) {
            /*
                Deleting an order in a certified POS involves registering the order as a PS.
                Then, registering it as a PR
                ultimately selling it as an NS at a price of 0.
            */
            try {
                this.ui.block();
                await this.pushCorrection(order);
                const serializedOrder = order.serializeForORM({ keepCommands: true });
                serializedOrder.blackbox_tax_category_a = 0;
                serializedOrder.blackbox_tax_category_b = 0;
                serializedOrder.blackbox_tax_category_c = 0;
                serializedOrder.blackbox_tax_category_d = 0;
                serializedOrder.receipt_type = "NS";
                serializedOrder.amount_tax = 0;
                serializedOrder.amount_total = 0;
                serializedOrder.lines = [];
                //add bb fields too);
                serializedOrder.blackbox_order_sequence = await this.getBlackboxSequence(order);
                serializedOrder.pos_version = this.config._server_version.server_version;
                const dataToSend = this.createOrderDataForBlackbox({
                    ...serializedOrder,
                    receipt_total: 0,
                    plu: order.getPlu([]),
                });
                const blackbox_response = await this.pushToBlackbox(dataToSend);
                order.uiState.receipt_type = "NS";
                order.blackbox_tax_category_a = 0;
                order.blackbox_tax_category_b = 0;
                order.blackbox_tax_category_c = 0;
                order.blackbox_tax_category_d = 0;
                order.setDataForPushOrderFromBlackbox(blackbox_response);
                await this.createLog(order, {}, false, false, false, true);
                await this.increaseCorrectionCounter(order.getTotalWithTax());
            } finally {
                this.ui.unblock();
            }
        }
        return super._onBeforeDeleteOrder(...arguments);
    },
    //#region Blackbox
    useBlackBoxBe() {
        return Boolean(this.config.iface_fiscal_data_module);
    },
    //#region Push Pro Forma
    async pushProFormaOrderLog(order) {
        order.updateReceiptType();
        const result = await this.pushOrderToBlackbox(order);
        if (result) {
            order.setDataForPushOrderFromBlackbox(result);
            await this.createLog(order);
        }
        return result;
    },
    async pushProFormaRefundOrder(order, lines = false) {
        const serializedOrder = order.serializeForORM({ keepCommands: true });
        const bbFields = await this.getBlackboxFields(order, "PR");
        Object.assign(serializedOrder, bbFields);
        if (lines) {
            serializedOrder.receipt_total = order.getTotalWithTaxOfLines(lines);
            serializedOrder.plu = order.getPlu(lines);
            serializedOrder.blackbox_tax_category_a = order.getTaxAmountByPercent(21, lines);
            serializedOrder.blackbox_tax_category_b = order.getTaxAmountByPercent(12, lines);
            serializedOrder.blackbox_tax_category_c = order.getTaxAmountByPercent(6, lines);
            serializedOrder.blackbox_tax_category_d = order.getTaxAmountByPercent(0, lines);
        } else {
            serializedOrder.plu = order.getPlu();
            serializedOrder.receipt_total = order.getTotalWithTax();
        }

        if (serializedOrder.receipt_total > 0) {
            serializedOrder.receipt_type = "PR";
        } else if (serializedOrder.receipt_total < 0) {
            serializedOrder.receipt_type = "PS";
        } else if (lines && lines.length > 0 && lines[0].getQuantity() < 0) {
            serializedOrder.receipt_type = "PS";
        } else if (lines && lines.length > 0 && lines[0].getQuantity() >= 0) {
            serializedOrder.receipt_type = "PR";
        } else if (order.lines && order.lines.length > 0 && order.lines[0].getQuantity() < 0) {
            serializedOrder.receipt_type = "PS";
        } else {
            serializedOrder.receipt_type = "PR";
        }

        //add bb fields too
        const dataToSend = this.createOrderDataForBlackbox(serializedOrder);
        const blackbox_response = await this.pushToBlackbox(dataToSend);
        if (!blackbox_response) {
            return;
        }
        await this.createLog(
            order,
            blackbox_response,
            serializedOrder.blackbox_order_sequence,
            serializedOrder.receipt_type,
            lines
        );
    },
    async pushCorrection(order, lines = []) {
        if (lines.length == 0) {
            lines = order.lines;
        }
        await this.pushProFormaOrderLog(order); //push the pro forma order to the blackbox and log
        await this.pushProFormaRefundOrder(order, lines); //push the pro forma refund order to the blackbox and log
    },
    getEmptyLogFields(order) {
        return {
            state: "paid",
            create_date: order.date_order,
            employee_name: this.getCashier().name,
            amount_total: 0,
            amount_paid: 0,
            currency_id: order.currency.id,
            pos_reference: order.pos_reference,
            config_name: this.config.name,
            session_id: this.session.id,
            lines: [],
            blackbox_order_sequence: order.blackbox_order_sequence,
            plu_hash: order.plu_hash,
            pos_version: this.config._server_version.server_version,
            blackbox_ticket_counters: order.blackbox_ticket_counters,
            blackbox_unique_fdm_production_number: order.blackbox_unique_fdm_production_number,
            certified_blackbox_identifier: this.config.certified_blackbox_identifier,
            blackbox_signature: order.blackbox_signature,
            change: 0,
        };
    },
    getLogFields(
        order,
        blackboxResponse = {},
        blackboxOrderSequence = false,
        receiptType = false,
        lines = false,
        emptyNS = false
    ) {
        if (emptyNS) {
            return this.getEmptyLogFields(order);
        }
        if (!receiptType) {
            receiptType = order.uiState.receipt_type || "PS";
        }
        if (!lines) {
            lines = order.lines;
        }
        const amount_total = Math.abs(order.getTotalWithTaxOfLines(lines));
        const amount_paid = Math.abs(order.getTotalPaid());
        const response = {
            state: order.state,
            create_date: order.date_order,
            employee_name: this.getCashier().name,
            amount_total: receiptType[1] == "R" ? -amount_total : amount_total,
            amount_paid: receiptType[1] == "R" ? -amount_paid : amount_paid,
            currency_id: order.currency.id,
            pos_reference: order.pos_reference,
            config_name: this.config.name,
            session_id: this.session.id,
            lines: this.getLineLogFields(order, receiptType, lines),
            blackbox_order_sequence: blackboxOrderSequence || order.blackbox_order_sequence,
            plu_hash: order.plu_hash,
            pos_version: this.config._server_version.server_version,
            blackbox_ticket_counters: order.blackbox_ticket_counters,
            blackbox_unique_fdm_production_number: order.blackbox_unique_fdm_production_number,
            certified_blackbox_identifier: this.config.certified_blackbox_identifier,
            blackbox_signature: order.blackbox_signature,
            change: order.getChange(),
        };
        if (Object.keys(blackboxResponse).length > 0) {
            response.blackbox_signature = blackboxResponse.signature;
            response.plu_hash = order.getPlu();
            response.blackbox_unique_fdm_production_number = blackboxResponse.fdm_number;
            response.blackbox_ticket_counters =
                receiptType +
                " " +
                blackboxResponse.ticket_counter +
                "/" +
                blackboxResponse.total_ticket_counter;
        }
        return response;
    },
    getLineLogFields(order, receipt_type, lines = false) {
        if (!lines) {
            lines = order.lines;
        }
        return lines.map((line) => ({
            product_name: line.product_id.display_name,
            qty: receipt_type[1] == "R" ? -line.getQuantity() : line.getQuantity(),
            price_subtotal_incl:
                receipt_type == "R"
                    ? -line.getAllPrices().priceWithTax
                    : line.getAllPrices().priceWithTax,
            discount: receipt_type == "R" ? -line.getDiscount() : line.getDiscount(),
        }));
    },
    async createLog(
        order,
        blackboxResponse = {},
        blackboxOrderSequence = false,
        receiptType = false,
        lines = false,
        emptyNS = false
    ) {
        await this.data.call("pos.order", "create_log", [
            [
                this.getLogFields(
                    order,
                    blackboxResponse,
                    blackboxOrderSequence,
                    receiptType,
                    lines,
                    emptyNS
                ),
            ],
        ]);
    },
    /**
     * #region Push to Blackbox
     * Push data to the blackbox using either longpolling or websocket.
     *
     * @param {Object} data The data to send to the blackbox.
     * @param {string} action The action to perform on the blackbox, e.g. "registerReceipt", "registerPIN", etc.
     * @return {Promise<Object>} The data returned from the blackbox, should look like this:
     * ```
     * {
     *      result: {
     *          signature: "123456789",
     *          vsc: "123456789",
     *          fdm_number: "123456789",
     *          ticket_counter: 12,
     *          total_ticket_counter: 99,
     *          time: "123456",
     *          date: "20240101",
     *          // error: {
     *          //     errorCode: "209000",
     *          //     errorMessage: "Fiscal Data Module real time clock corrupt.",
     *          // },
     *          error: {
     *              errorCode: "000000",
     *              errorMessage: "No error.",
     *          },
     *      },
     * };
     * ```
     */
    async pushDataToBlackbox(data, action) {
        const fdm = this.hardwareProxy.deviceControllers.fiscal_data_module;

        return new Promise((resolve, reject) => {
            this.iotHttp.action(
                fdm.iotId,
                fdm.identifier,
                { action, high_level_message: data },
                (message) => resolve(message),
                (message) => reject(message)
            );
        });
    },
    async pushOrderToBlackbox(order) {
        await this.updateBlackboxFields(order);
        const insz = order.uiState.insz?.[1];
        const dataToSend = this.createOrderDataForBlackbox({
            ...order.serializeForORM({ keepCommands: true }),
            clock: order.uiState.clock,
            insz: insz,
            receipt_type: order.uiState.receipt_type,
            receipt_total: order.getTotalWithTax(),
            plu: order.getPlu(),
        });
        return this.pushToBlackbox(dataToSend);
    },
    async pushToBlackbox(dataToSend) {
        try {
            const data = await this.pushDataToBlackbox(dataToSend, "registerReceipt");
            const result = this.extractResult(data);
            if (!result?.error?.errorCode.startsWith("000")) {
                throw result.error;
            }
            return result;
        } catch (err) {
            //the catch might actually not be an error
            const result = this.extractResult(err);
            if (result?.error?.errorCode.startsWith("000")) {
                return result;
            }
            if (err.errorCode?.startsWith("202")) {
                this.dialog.add(NumberPopup, {
                    title: _t("Enter Pin Code"),
                    getPayload: (num) => {
                        this.pushDataToBlackbox(num, "registerPIN");
                    },
                });
                throw new Error(_t("Pin code required"));
            } else if (err.status === "disconnected") {
                throw new BlackboxError(err.status);
            } else {
                throw new BlackboxError(err.errorCode, err.errorMessage);
            }
        }
    },
    extractResult(data) {
        if (Array.isArray(data.result)) {
            return data.result[0];
        } else {
            return data.result;
        }
    },
    async getBlackboxFields(order, receiptType = false) {
        return {
            blackbox_tax_category_a: order.getTaxAmountByPercent(21),
            blackbox_tax_category_b: order.getTaxAmountByPercent(12),
            blackbox_tax_category_c: order.getTaxAmountByPercent(6),
            blackbox_tax_category_d: order.getTaxAmountByPercent(0),
            blackbox_order_sequence: await this.getBlackboxSequence(order, receiptType),
            pos_version: this.config._server_version.server_version,
        };
    },
    async updateBlackboxFields(order) {
        const bbFields = await this.getBlackboxFields(order);
        Object.assign(order, bbFields);
        if (!order.uiState.receipt_type) {
            order.updateReceiptType();
        }
    },
    createOrderDataForBlackbox(order) {
        return {
            date: luxon.DateTime.now().toFormat("yyyyMMdd"),
            ticket_time: luxon.DateTime.now().toFormat("HHmmss"),
            insz_or_bis_number:
                order.insz ||
                (this.config.module_pos_hr
                    ? this.session._employee_insz_or_bis_number[this.getCashier().id]
                    : this.user.insz_or_bis_number),
            ticket_number: order.blackbox_order_sequence.toString(),
            type: order.receipt_type,
            receipt_total: Math.abs(order.receipt_total).toFixed(2).toString().replace(".", ""),
            vat1: order.blackbox_tax_category_a
                ? Math.abs(order.blackbox_tax_category_a).toFixed(2).replace(".", "")
                : "",
            vat2: order.blackbox_tax_category_b
                ? Math.abs(order.blackbox_tax_category_b).toFixed(2).replace(".", "")
                : "",
            vat3: order.blackbox_tax_category_c
                ? Math.abs(order.blackbox_tax_category_c).toFixed(2).replace(".", "")
                : "",
            vat4: order.blackbox_tax_category_d
                ? Math.abs(order.blackbox_tax_category_d).toFixed(2).replace(".", "")
                : "",
            plu: order.plu,
            clock: order.clock ? order.clock : false,
        };
    },
    async getBlackboxSequence(order, receiptType = false) {
        const functionToCall = (receiptType || order.uiState.receipt_type || "p")
            .toLowerCase()
            .startsWith("p")
            ? "get_PS_sequence_next"
            : "get_NS_sequence_next";
        return parseInt(await this.data.call("pos.config", functionToCall, [[this.config.id]]));
    },
});
