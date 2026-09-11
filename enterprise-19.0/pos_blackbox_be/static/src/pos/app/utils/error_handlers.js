import { registry } from "@web/core/registry";
import { _t } from "@web/core/l10n/translation";
import { BlackboxError } from "@pos_blackbox_be/pos/app/utils/blackbox_error";
import { RetryFdmPopup } from "@pos_blackbox_be/pos/app/components/popups/retry_fdm_popup/retry_fdm_popup";

function blackboxErrorHandler(env, error, originalError) {
    if (originalError instanceof BlackboxError) {
        const disconnectedError = _t(
            "The IoT Box is connected, but the Fiscal Data Module isn't. In order to continue," +
                " you need to connect the Fiscal Data Module to the IoT Box.\n\n" +
                "If done already, try to:\n" +
                "1/ check the cable between the IoT Box and the Fiscal Data Module\n" +
                "2/ unplug the Fiscal Data Module, then plug it again\n"
        );
        const defaultError = _t("Internal blackbox error, the blackbox may have disconnected.");
        const currentError =
            originalError.code === "disconnected" ? disconnectedError : defaultError;
        env.services.dialog.add(RetryFdmPopup, {
            title: _t("Fiscal Data Module error: ") + originalError.code,
            message: originalError.message || currentError,
            retry: originalError.retry,
        });
        return true;
    }
}
registry.category("error_handlers").add("blackboxErrorHandler", blackboxErrorHandler);
