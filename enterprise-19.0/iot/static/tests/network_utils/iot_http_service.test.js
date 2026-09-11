import { beforeEach, describe, expect, test } from "@odoo/hoot";
import {
    makeMockEnv,
    models,
    defineModels,
    patchWithCleanup,
} from "@web/../tests/web_test_helpers";
import { uuid } from "@web/core/utils/strings";
import { browser } from "@web/core/browser/browser";

import { IotHttpService } from "@iot/network_utils/iot_http_service";

class IotChannel extends models.Model {
    get_iot_channel() {
        return "mockChannel";
    }
}

defineModels({ IotChannel });

class DummyOrm {
    constructor(returned) {
        this._returned = returned;
    }
    async searchRead(model, domain, fields) {
        return [this._returned];
    }
}

describe("iot_http_service", () => {
    let iotHttpService;
    let websocketMessages;
    let notification;
    let longpolling;
    let websocket;
    let webRtc;
    let orm;
    let onSuccess;
    let onFailure;
    let calledCallback = 'pending';

    beforeEach(async () => {
        await makeMockEnv();
        websocketMessages = [];
        notification = {
            added: [],
            add: function (msg, opts) {
                this.added.push({ msg, opts });
            },
        };

        orm = new DummyOrm({ ip: "127.0.0.1", identifier: "box-123" });
        patchWithCleanup(browser, {
            fetch: async (_url) => {
                return true
            }
        })

        // if we should receive a failed response from the IoT Box
        let webRtcShouldFail = false;
        let longpollingShouldFail = false;
        let websocketShouldFail = false;

        // if calling the action should fail
        let webRtcShouldThrow = false;
        let longpollingShouldThrow = false;
        let websocketShouldThrow = false;

        webRtc = {
            sendMessage: async (identifier, payload, actionId, _messageType) => {
                if (webRtcShouldThrow) {
                    throw new Error("webrtc sendMessage failed");
                }
                return actionId || uuid();
            },
            onMessage: async (identifier, deviceIdentifier, actionId, onSuccess, onFailure) => {
                if (webRtcShouldThrow) {
                    throw new Error("webrtc onMessage failed");
                }
                if (webRtcShouldFail) {
                    onFailure({ status: "disconnected" }, deviceIdentifier);
                    return;
                }
                onSuccess({ status: "success", device_identifier: deviceIdentifier }, deviceIdentifier);
            },
            setThrow: (v) => { webRtcShouldThrow = v; },
            setFail: (v) => { webRtcShouldFail = v; },
        };

        longpolling = {
            sendMessage: async (ip, payload, actionId, _hasFallback) => {
                if (longpollingShouldThrow) {
                    throw new Error("longpolling sendMessage failed");
                }
                return actionId || uuid();
            },
            onMessage: (ip, deviceIdentifier, onSuccess, onFailure, actionId) => {
                if (longpollingShouldThrow) {
                    throw new Error("longpolling onMessage failed");
                }
                if (longpollingShouldFail) {
                    onFailure({ status: "disconnected" }, deviceIdentifier);
                    return;
                }
                onSuccess({ status: "success", device_identifier: deviceIdentifier }, deviceIdentifier);
            },
            setThrow: (v) => { longpollingShouldThrow = v; },
            setFail: (v) => { longpollingShouldFail = v; },
        };

        websocket = {
            sendMessage: async (identifier, payload, actionId, messageType) => {
                if (websocketShouldThrow) {
                    throw new Error("websocket sendMessage failed");
                }
                websocketMessages.push({ identifier, payload, actionId, messageType });
                return actionId || uuid();
            },
            onMessage: (identifier, deviceIdentifier, onSuccess, onFailure, _messageType, _actionId) => {
                if (websocketShouldThrow) {
                    throw new Error("websocket onMessage failed");
                }
                if (websocketShouldFail) {
                    onFailure({ status: "disconnected" }, deviceIdentifier);
                    return;
                }
                onSuccess({ status: "success", device_identifier: deviceIdentifier }, deviceIdentifier);
            },
            setThrow: (v) => { websocketShouldThrow = v; },
            setFail: (v) => { websocketShouldFail = v; },
        };

        onSuccess = () => { calledCallback = 'onSuccess' };
        onFailure = () => { calledCallback = 'onFailure' };

        iotHttpService = new IotHttpService(
            longpolling,
            websocket,
            webRtc,
            notification,
            orm
        );
    });

    describe("action", () => {
        test("uses WebRTC first and succeeds", async () => {
            await iotHttpService.action(1, "device-1", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe("local");
        });

        test("fallback to longpolling when WebRTC fails", async () => {
            webRtc.setThrow(true);
            await iotHttpService.action(1, "device-2", { a: "b" }, onSuccess, onFailure);

            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe("local");
        });

        test("fallback to websocket when both WebRTC and longpolling fail", async () => {
            webRtc.setThrow(true);
            longpolling.setThrow(true);

            await iotHttpService.action(1, "device-3", { x: "y" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe("online");
        });

        test("all methods fail and onFailure is invoked with disconnected status", async () => {
            webRtc.setThrow(true);
            longpolling.setThrow(true);
            websocket.setThrow(true);

            await iotHttpService.action(1, "device-4", { something: "else" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onFailure');
            expect(iotHttpService.connectionStatus).toBe("offline");
        });

        test("invalid iotBoxId (array unwraps Many2one)", async () => {
            await iotHttpService.action([1], "device-array", { foo: "bar" }, onSuccess);
            expect(calledCallback).toBe('onSuccess');
        });

        test("recent longpolling failure short-circuits longpolling path", async () => {
            // simulate that longpolling just failed
            iotHttpService.longpollingFailedTimestamp = Date.now();
            webRtc.setThrow(true);
            // longpolling should be skipped due to recent failure, so websocket is used
            await iotHttpService.action(1, "device-5", { test: "val" }, onSuccess);
            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe("online");
        });

        test("webrtc onMessage calls back onFailure", async () => {
            webRtc.setFail(true); // make WebRTC onMessage report failure
            await iotHttpService.action(1, "device-webrtc-fail", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onFailure');
            expect(iotHttpService.connectionStatus).toBe("local"); // longpolling wins after webrtc onMessage failure
        });

        test("longpolling onMessage calls back onFailure", async () => {
            webRtc.setThrow(true);
            longpolling.setFail(true); // make longpolling onMessage report failure
            await iotHttpService.action(1, "device-longpolling-fail", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onFailure');
            expect(iotHttpService.connectionStatus).toBe("local"); // websocket wins after longpolling onMessage failure
        });

        test("websocket onMessage calls back onFailure", async () => {
            webRtc.setThrow(true);
            longpolling.setThrow(true);
            websocket.setFail(true); // make websocket onMessage report failure
            await iotHttpService.action(1, "device-websocket-fail", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onFailure');
            expect(iotHttpService.connectionStatus).toBe("online"); // all methods failed
        });

        test('force switch between longpolling/websocket', async () => {
            webRtc.setThrow(true);
            longpolling.setThrow(true)
            await iotHttpService.action(1, "mock-device", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe('online');

            await iotHttpService.toggleMode('mockIp');
            expect(iotHttpService.longpollingFailedTimestamp).toBe(null);
            expect(iotHttpService.connectionStatus).toBe('local');

            longpolling.setThrow(false); // don't force longpolling failure this time, we want to see if we pass through it
            await iotHttpService.action(1, "mock-device", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe('local');

            await iotHttpService.toggleMode('mockIp'); // switch back to websocket
            await iotHttpService.action(1, "mock-device", { foo: "bar" }, onSuccess, onFailure);
            expect(calledCallback).toBe('onSuccess');
            expect(iotHttpService.connectionStatus).toBe('online');
        });
    });
});
