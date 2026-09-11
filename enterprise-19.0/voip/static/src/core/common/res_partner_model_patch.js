import { ResPartner } from "@mail/core/common/res_partner_model";

import { patch } from "@web/core/utils/patch";

patch(ResPartner.prototype, {
    /**
     * Can be overridden to change the name.
     *
     * @returns {string}
     */
    get voipName() {
        return this.name || "";
    },
    get jobDescription() {
        const info = [];
        if (this.commercial_company_name) {
            info.push(this.commercial_company_name);
        }
        // ⚠ French: function = job position
        if (this.function) {
            info.push(this.function);
        }
        return info.join(" - ");
    },
});
