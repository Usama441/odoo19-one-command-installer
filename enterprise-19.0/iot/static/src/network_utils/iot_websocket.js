import { uuid } from "@web/core/utils/strings";

/**
 * Class to handle Websocket connections
 */
export class IotWebsocket {
    listeners = {};

    constructor() {
        this.setup(...arguments);
    }

    async setup({ bus_service, orm, lazy_session }) {
        this.busService = bus_service;
        this.orm = orm;
        if (lazy_session) {
            lazy_session.getValue("iot_channel", (iotChannel) => {
                this.iotChannel = iotChannel;
            });
        } else {
            this.iotChannel = await this.orm.call("iot.channel", "get_iot_channel", [0]);
        }
    }

    /**
     * Send a message to the IoT Box
     * @param iotBoxIdentifier Identifier of the IoT Box
     * @param message Data to send to the device
     * @param messageId Unique identifier for the message (optional)
     * @param messageType Type of message to send (optional)
     * @returns {Promise<*>} The message ID
     */
    async sendMessage(iotBoxIdentifier, message, messageId = null, messageType = 'iot_action') {
        messageId ??= uuid();

        await this.orm.call("iot.channel", "send_message", [
            { iot_identifiers: [iotBoxIdentifier], session_id: messageId, ...message }, messageType
        ]);

        return messageId;
    }

    /**
     * Add a listener for events/messages coming from the IoT Box.
     * This method allows defining callbacks for success and failure cases.
     * @param iotBoxIdentifier Identifier of the IoT Box
     * @param deviceIdentifier Identifier of the device connected to the IoT Box
     * @param onSuccess Callback to run when a message is received (can return ``message``, ``deviceIdentifier``, and ``messageId``)
     * @param onFailure Callback to run when the request fails (can return ``deviceIdentifier`` and ``messageId``)
     * @param messageType The type of message to listen for (optional)
     * @param requestId The request ID to listen for (optional)
     */
    onMessage(
        iotBoxIdentifier,
        deviceIdentifier,
        onSuccess = (_message, _deviceIdentifier, _messageId) => {},
        onFailure = (_message, _deviceIdentifier, _messageId) => {},
        messageType = 'operation_confirmation',
        requestId = null
    ) {
        if (!this.iotChannel) {
            console.error("No IoT Channel found");
            return;
        }

        // add the listener to the list of listeners
        this.pushListener(iotBoxIdentifier, deviceIdentifier, messageType, onSuccess, onFailure);

        const timeoutId = setTimeout(() => {
            this.busService.unsubscribe(messageType);
            console.debug("Websocket timeout for", iotBoxIdentifier, deviceIdentifier, requestId);
            this.callbackListeners(iotBoxIdentifier, deviceIdentifier, messageType, requestId, {
                status: "error",
                message: "Timeout waiting for IoT Box response, please try again.",
            });
        }, 6000); // error callback if the listener is not called within 6 seconds
        this.busService.addChannel(this.iotChannel);
        this.busService.subscribe(messageType, (payload) => {
            const { session_id, iot_box_identifier, device_identifier, message } = payload;
            if (iot_box_identifier !== iotBoxIdentifier || device_identifier !== deviceIdentifier || (requestId && session_id !== requestId)) {
                return;
            }

            this.callbackListeners(iotBoxIdentifier, deviceIdentifier, messageType, session_id, message);
            clearTimeout(timeoutId);
        });
    }

    /**
     * Register a callback to be called when the device sends a success or failure message/event
     * Both pop and push listener methods are used to handle callbacks to multiple listeners for the same message
     * @param iotBoxIdentifier Identifier of the IoT Box
     * @param deviceIdentifier Identifier of the device connected to the IoT Box
     * @param messageType The type of message to listen for
     * @param onSuccess The callback to run when a message is received
     * @param onFailure The callback to run when the request fails
     */
    pushListener(iotBoxIdentifier, deviceIdentifier, messageType, onSuccess, onFailure) {
        const currentIotBox = this.listeners[iotBoxIdentifier] ??= {};
        const currentDeviceIdentifier = currentIotBox[deviceIdentifier] ??= {};
        const callbacks = currentDeviceIdentifier[messageType] ??= { onSuccess: [], onFailure: [] };

        callbacks.onSuccess.push(onSuccess);
        callbacks.onFailure.push(onFailure);
    }

    /**
     * Execute all callbacks for a specific device and unregister them.
     * Both pop and push listener methods are used to handle callbacks to multiple listeners for the same message
     * @param iotBoxIdentifier Identifier of the IoT Box
     * @param deviceIdentifier Identifier of the device connected to the IoT Box
     * @param messageType The type of message to listen for
     * @param messageId The message ID
     * @param message The message received
     */
    callbackListeners(iotBoxIdentifier, deviceIdentifier, messageType, messageId, message) {
        const listenedIotBox = this.listeners[iotBoxIdentifier];
        const listeners = listenedIotBox?.[deviceIdentifier]?.[messageType];
        if (!listeners) {
            return;
        }

        // Run the callbacks
        const success = message.status === "success" || message.status?.status === "connected"; // 'connected' is the serial driver success status
        const callbacks = success ? listeners.onSuccess : listeners.onFailure;
        for (const callback of callbacks) {
            callback(message, deviceIdentifier, messageId);
        }

        // Remove the listeners (cleanup)
        delete listenedIotBox[deviceIdentifier][messageType];

        // If there are no more listeners for the device, remove the device
        if (Object.keys(listenedIotBox[deviceIdentifier]).length === 0) {
            delete listenedIotBox[deviceIdentifier];
        }

        // If there are no more listeners for the IoT Box, remove the IoT Box
        if (Object.keys(listenedIotBox).length === 0) {
            delete this.listeners[iotBoxIdentifier];
        }
    }
}
