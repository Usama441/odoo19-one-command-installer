import { registry } from "@web/core/registry";
import { post, formatEndpoint } from "@iot_base/network_utils/http";
import { uuid } from "@web/core/utils/strings";
import { IotWebsocket } from "@iot/network_utils/iot_websocket";
import { _t } from "@web/core/l10n/translation";
import { IotWebRtc } from "./iot_webrtc";
import { browser } from "@web/core/browser/browser";

export const PRINTER_MESSAGES = {
    ERROR_FAILED: _t("Failed to initiate print"),
    ERROR_OFFLINE: _t("Printer is not ready"),
    ERROR_TIMEOUT: _t("Printing timed out"),
    ERROR_NO_PAPER: _t("Out of paper"),
    ERROR_UNREACHABLE: _t("Printer is unreachable"),
    ERROR_UNKNOWN: _t("Unknown printer error occurred"),
    WARNING_LOW_PAPER: _t("Paper is low"),
};

export const FDM_MESSAGES = {
    '000': _t("Blackbox is running and operational"),
    '001': _t("PIN accepted."),
    101: _t("Fiscal Data Module memory 90% full."),
    102: _t("Repeated request. This request was already handled by the fiscal data module."),
    103: _t("Operation wasn't saved on the blackbox"),
    199: _t("Unspecified warning."),
    201: _t("No Vat Signing Card or Vat Signing Card broken."),
    202: _t("Please activate the Vat Signing Card with PIN."),
    203: _t("Vat Signing Card blocked."),
    204: _t("Invalid PIN."),
    205: _t("Fiscal Data Module memory full."),
    206: _t("Unknown identifier."),
    207: _t("Invalid data in message sent to the blackbox."),
    208: _t("Fiscal Data Module not operational. Please restart the blackbox"),
    209: _t("Fiscal Data Module real time clock corrupt."),
    210: _t("Vat Signing Card not compatible with Fiscal Data Module."),
    299: _t("Unspecified error."),
    300: _t("Blackbox responded with invalid response. Please check the cable connection and the power supply, then retry. Restart if necessary"),
    301: _t("Blackbox did not respond to your request. This usually means it has disconnected. Please check its cable connection and its power supply. Restart if necessary."),
};

/**
 * Class to handle IoT actions
 * The class is used to send actions to IoT devices and handle fallbacks
 * in case the request fails: it will try to send the request using
 * HTTP POST method and then using the websocket.
 */
export class IotHttpService {
    longpollingFailedTimestamp = null;
    connectionStatus = "local"; // local, online, offline
    connectionTypes = [
        this._webRtc.bind(this),
        this._longpolling.bind(this),
        this._websocket.bind(this)
    ];

    /**
     *
     * @param {import("@iot_base/network_utils/longpolling").IotLongpolling} longpolling Longpolling service
     * @param {import("@iot/network_utils/iot_websocket").IotWebsocket} websocket Websocket service
     * @param {import("@iot/network_utils/iot_webrtc").IotWebRtc} webRtc WebRTC service
     * @param notification Notification service
     * @param orm ORM service
     */
    constructor(longpolling, websocket, webRtc, notification, orm) {
        this.longpolling = longpolling;
        this.websocket = websocket;
        this.webRtc = webRtc;
        this.notification = notification;
        this.orm = orm;
    }

    onFailure(_message, deviceIdentifier, _messageId) {
        this.notification.add(_t("Failed to reach the IoT Box for device: %s", deviceIdentifier), { type: "danger" });
    }

    async getIotBoxData(iotBoxId) {
        const [iotBoxData] = await this.orm.searchRead("iot.box", [["id", "=", iotBoxId]], ["ip", "identifier"]);
        return iotBoxData;
    }

    _ensureLongpollingEnabled() {
        if (
            this.longpollingFailedTimestamp &&
            Date.now() - this.longpollingFailedTimestamp < 20 * 60 * 1000
        ) {
            throw new Error("Longpolling is temporarily disabled due to a recent failure.");
        }
    }

    async _webRtc({ identifier, deviceIdentifier, data, messageId, onSuccess, onFailure }) {
        await this.webRtc.onMessage(identifier, deviceIdentifier, messageId, onSuccess, onFailure);
        if (data) {
            await this.webRtc.sendMessage(identifier, { device_identifier: deviceIdentifier, data }, messageId);
        }
        this.connectionStatus = "local";
    }

    async _longpolling({ ip, deviceIdentifier, data, messageId, onSuccess, onFailure }) {
        this._ensureLongpollingEnabled();
        try {
            this.longpolling.onMessage(ip, deviceIdentifier, onSuccess, onFailure, messageId);
            if (data) {
                const response =
                    await this.longpolling.sendMessage(ip, { device_identifier: deviceIdentifier, data }, messageId, true);
                if (response?.result === false) {
                    onFailure({status: "disconnected"}, deviceIdentifier, messageId);
                }
            }
        } catch (e) {
            this.longpollingFailedTimestamp = Date.now();
            throw e;
        }
        this.connectionStatus = "local";
    }

    async _websocket({ identifier, deviceIdentifier, data, messageId, onSuccess, onFailure }) {
        const onFailureWithTimeout = (...args) => {
            onFailure(...args);
            this.connectionStatus = "offline";
        };
        this.websocket.onMessage(identifier, deviceIdentifier, onSuccess, onFailureWithTimeout, "operation_confirmation", messageId);
        if (data) {
            await this.websocket.sendMessage(identifier, { device_identifiers: [deviceIdentifier], ...data }, messageId);
        }
        this.connectionStatus = "online";
    }

    async _attemptFallbacks({ iotBoxId, deviceIdentifier, onFailure }) {
        if (!["number", "string"].includes(typeof iotBoxId)) {
            iotBoxId = iotBoxId[0]; // iotBoxId is the ``Many2one`` field, we need the actual ID
        }

        const { ip, identifier } = await this.getIotBoxData(iotBoxId);
        const params = { ip, identifier, ...arguments[0] };

        for (const connectionType of this.connectionTypes) {
            try {
                return await connectionType(params);
            } catch (e) {
                console.debug("IoT Box action: attempted method failed, attempting another protocol.", e);
            }
        }

        // If all the connection types failed, run the onFailure callback
        this.connectionStatus = "offline";
        onFailure({ status: "disconnected" }, deviceIdentifier);
    }

    /**
     * Listen for events on the IoT Box
     * @param iotBoxId IoT Box record ID
     * @param deviceIdentifier Identifier of the device connected to the IoT Box
     * @param {(message: Record<string, unknown>, deviceId: string) => void} onSuccess Callback to run when a message is received
     * @param {(message: Record<string, unknown>, deviceId: string) => void} onFailure Callback to run when the request fails
     * @param {string|null} messageId Unique identifier for the message (optional)
     * @returns {Promise<void>}
     */
    async onMessage(
        iotBoxId,
        deviceIdentifier,
        onSuccess = () => {},
        onFailure = (...args) => this.onFailure(...args),
        messageId = null,
    ) {
        // Attempt to listen for messages using the defined connection types
        await this._attemptFallbacks({
            iotBoxId,
            deviceIdentifier,
            messageId,
            onSuccess,
            onFailure,
        });
    }

    /**
     * Call for an action method on the IoT Box
     * @param iotBoxId IoT Box record ID
     * @param deviceIdentifier Identifier of the device connected to the IoT Box
     * @param data Data to send
     * @param {(message: Record<string, unknown>, deviceId: string) => void} onSuccess Callback to run when a message is received
     * @param {(message: Record<string, unknown>, deviceId: string) => void} onFailure Callback to run when the request fails
     * @param {string|null} messageId Unique identifier for the message (optional)
     * @returns {Promise<void>}
     */
    async action(
        iotBoxId,
        deviceIdentifier,
        data,
        onSuccess = () => {},
        onFailure = (...args) => this.onFailure(...args),
        messageId = null,
    ) {
        messageId ??= uuid();

        await this._attemptFallbacks({
            iotBoxId,
            deviceIdentifier,
            data,
            messageId,
            onSuccess,
            onFailure,
        });
    }

    async toggleMode(iotBoxIp) {
        if (this.connectionStatus !== "local") {
            try {
                await browser.fetch(formatEndpoint(iotBoxIp, '/iot_drivers/ping'));
                this.longpollingFailedTimestamp = null;
                this.connectionStatus = "local";
            } catch {
                console.debug("IoT Box is unreachable via local network, can't toggle to local mode.");
            }
            return
        }
        this.longpollingFailedTimestamp = Date.now();
        this.connectionStatus = "online";
    }
}


export const iotHttpService = {
    dependencies: ["notification", "orm", "bus_service", "iot_longpolling", "lazy_session"],

    start(env, { notification, orm, bus_service, iot_longpolling, lazy_session }) {
        const iotWebsocket = new IotWebsocket({ bus_service, orm, lazy_session });
        const iotWebRtc = new IotWebRtc(bus_service, iotWebsocket);

        const longpolling = {
            sendMessage: iot_longpolling.sendMessage.bind(iot_longpolling),
            onMessage: iot_longpolling.onMessage.bind(iot_longpolling),
        };

        const websocket = {
            sendMessage: iotWebsocket.sendMessage.bind(iotWebsocket),
            onMessage: iotWebsocket.onMessage.bind(iotWebsocket),
        };

        const iot = new IotHttpService(
            iot_longpolling,
            iotWebsocket,
            iotWebRtc,
            notification,
            orm
        );
        const action = iot.action.bind(iot);
        const onMessage = iot.onMessage.bind(iot);
        const toggleMode = iot.toggleMode.bind(iot);

        // Expose only those functions to the environment
        // status is a getter to have a reactive value
        return {
            post, action, longpolling, websocket, toggleMode, onMessage, get status() {
                return iot.connectionStatus;
            }
        };
    },
};

registry.category("services").add("iot_http", iotHttpService);
