import { _t } from "@web/core/l10n/translation";
import { registry } from "@web/core/registry";
import { browser } from "@web/core/browser/browser"
import { IOT_REPORT_PREFERENCE_LOCAL_STORAGE_KEY } from "@iot/client_action/delete_local_storage";
import { uuid } from "@web/core/utils/strings";

/**
 * Method to print the report with the selected devices
 *
 * @param env Environment
 * @param args Arguments to render the report (report_id, active_record_ids, report_data)
 * @param selected_device_ids Selected device ids (those stored in local storage)
 * @returns {Promise<void>}
 */
export async function printReport(env, args, selected_device_ids) {
    const orm = env.services.orm;
    const notification = env.services.notification;
    const iotHttp = env.services.iot_http;

    const [report_id, active_record_ids, report_data] = args;
    const jobs = await orm.call(
        "ir.actions.report", "render_document",
        [report_id, selected_device_ids, active_record_ids, report_data]
    );

    for (const job of jobs) {
        const { iotBoxId, deviceIdentifier, deviceName, document } = job;
        const removeSendingNotification = notification.add(_t("Sending document to printer %s...", deviceName), {
            type: "info",
            sticky: true,
        });

        await iotHttp.action(iotBoxId, deviceIdentifier, { document, print_id: uuid() }, () => {
            removeSendingNotification?.();
            notification.add(_t("Started printing operation on printer %s...", deviceName), { type: "success" });
        });
    }
}

async function iotReportActionHandler(action, options, env) {
    if (action.device_ids && action.device_ids.length) {
        const orm = env.services.orm;

        action.data ??= {};
        action.data["device_ids"] = action.device_ids;
        const reportId = action.id;
        const deviceSettingsByReport = JSON.parse(browser.localStorage.getItem(IOT_REPORT_PREFERENCE_LOCAL_STORAGE_KEY));
        const onClose = options.onClose;
        const deviceSettings = deviceSettingsByReport?.[reportId];
        const args = [action.id, action.context.active_ids, action.data, uuid(), deviceSettings?.selectedDevices];
        if (!deviceSettings || !deviceSettings.skipDialog) {
            // Open IoT devices selection wizard
            const actionWizard = await orm.call("ir.actions.report", "get_action_wizard", args);
            await env.services.action.doAction(actionWizard);

            // We do this to ensure the handler only returns once the printer
            // has been selected and is printing. Otherwise, if multiple reports
            // try to print in a row you cannot select the printer as the popup disappears.
            await new Promise((resolve) => {
                const onPrinterSelected = (event) => {
                    if (event.detail === args[3]) {
                        env.bus.removeEventListener("printer-selected", onPrinterSelected);
                        resolve();
                    }
                };
                env.bus.addEventListener("printer-selected", onPrinterSelected);
            });
        } else {
            env.services.ui.block();
            await printReport(env, args, deviceSettings.selectedDevices);
            env.services.ui.unblock();

            // We close here to prevent premature closure if the device selection modal is displayed.
            env.services.action.doAction({ type: "ir.actions.act_window_close" }, { onClose });
        }

        onClose?.();
        return true;
    }
}

registry
    .category("ir.actions.report handlers")
    .add("iot_report_action_handler", iotReportActionHandler);
