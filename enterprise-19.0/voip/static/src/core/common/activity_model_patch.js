import { fields } from "@mail/core/common/record";
import { Activity } from "@mail/core/common/activity_model";

import { patch } from "@web/core/utils/patch";


/** @type {import("models").Activity} */
const activityPatch = {
    /** @override */
    setup() {
        super.setup();
        this.partner = fields.One("res.partner");
    },
};
patch(Activity.prototype, activityPatch);
