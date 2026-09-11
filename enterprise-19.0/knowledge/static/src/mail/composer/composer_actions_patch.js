import { ComposerAction } from "@mail/core/common/composer_actions";
import { patch } from "@web/core/utils/patch";

patch(ComposerAction.prototype, {
    _condition({ owner }) {
        // Always disable the send-message action for knowledge comment composer.
        // This is to avoid having two buttons for sending messages.
        if (this.id === "send-message" && owner.env.inKnowledge) {
            return false;
        }
        return super._condition(...arguments);
    },
});
