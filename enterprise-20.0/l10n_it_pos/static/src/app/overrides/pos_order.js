import { PosOrder } from "@point_of_sale/app/models/pos_order";
import { patch } from "@web/core/utils/patch";

patch(PosOrder.prototype, {
    _convertToDDMMYYYY(date) {
        const [day, month, year] = date.split("/");
        return `${day.padStart(2, "0")}${month.padStart(2, "0")}${year}`;
    },

    get isRefunded() {
        return this.lines.every((line) => line.qty < 0);
    },

    getRefundInfo() {
        let {
            it_z_rep_number,
            fiscal_it_receipt_number,
            it_fiscal_receipt_date,
            it_fiscal_printer_serial_number,
        } = this.refunded_order_id;

        it_z_rep_number = it_z_rep_number ? String(it_z_rep_number).padStart(4, "0") + " " : "";
        fiscal_it_receipt_number = fiscal_it_receipt_number
            ? String(fiscal_it_receipt_number).padStart(4, "0") + " "
            : "";
        it_fiscal_receipt_date = it_fiscal_receipt_date
            ? this._convertToDDMMYYYY(String(it_fiscal_receipt_date)) + " "
            : "";
        it_fiscal_printer_serial_number = it_fiscal_printer_serial_number
            ? it_fiscal_printer_serial_number
            : this.config.it_fiscal_printer_serial_number;

        return `REFUND ${it_z_rep_number}${fiscal_it_receipt_number}${it_fiscal_receipt_date}${it_fiscal_printer_serial_number}`;
    },

    get fiscal_it_receipt_number() {
        if (!this.it_fiscal_receipt_number) {
            return false;
        }
        return this.it_fiscal_receipt_number.includes("|")
            ? this.it_fiscal_receipt_number.split("|")[0]
            : this.it_fiscal_receipt_number;
    },

    get it_fiscal_printer_serial_number() {
        return this.it_fiscal_receipt_number && this.it_fiscal_receipt_number.includes("|")
            ? this.it_fiscal_receipt_number.split("|")[1]
            : false;
    },
});
