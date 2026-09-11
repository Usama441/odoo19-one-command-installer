import { Component } from "@odoo/owl";
import { usePos } from "@point_of_sale/app/hooks/pos_hook";
import { PrintRecMessage } from "@l10n_it_pos/app/fiscal_printer/commands";

export class Header extends Component {
    static template = "l10n_it_pos.FiscalDocumentHeader";

    static components = {
        PrintRecMessage,
    };

    setup() {
        this.pos = usePos();
        this.order = this.pos.getOrder();
    }
}
