import { IoTPrinter } from "@pos_iot/app/utils/printer/iot_printer";
import { DeviceController } from "@iot_base/device_controller";
import { SelfOrder, selfOrderService } from "@pos_self_order/app/services/self_order_service";
import { patch } from "@web/core/utils/patch";

patch(selfOrderService, {
    dependencies: [...selfOrderService.dependencies, "iot_longpolling", "iot_http"],
});

patch(SelfOrder.prototype, {
    async setup(env, services) {
        this.iot_longpolling = services.iot_longpolling;
        this.iotHttpService = services.iot_http;
        await super.setup(...arguments);

        if (!this.config.iface_print_via_proxy || this.config.self_ordering_mode !== "kiosk") {
            return;
        }

        const device = new DeviceController(this.iot_longpolling, {
            iot_ip: this.config.iface_printer_id.iot_ip,
            identifier: this.config.iface_printer_id.identifier,
            iot_id: { id: this.config.iface_printer_id.iot_id },
        });
        this.printer.setPrinter(
            new IoTPrinter({
                device,
                iot_http: this.iotHttpService,
                access_token: this.access_token,
            })
        );
    },

    filterPaymentMethods(paymentMethods) {
        const otherPaymentMethods = super.filterPaymentMethods(...arguments);
        const iotPaymentMethods = paymentMethods.filter(
            (paymentMethod) => paymentMethod.iot_device_id != null
        );
        return [...new Set([...otherPaymentMethods, ...iotPaymentMethods])];
    },

    createPrinter(printer) {
        if (printer.device_identifier && printer.printer_type === "iot") {
            const device = new DeviceController(this.iot_longpolling, {
                iot_ip: printer.proxy_ip,
                identifier: printer.device_identifier,
            });
            return new IoTPrinter({
                device,
                iot_http: this.iotHttpService,
                access_token: this.access_token,
            });
        } else {
            return super.createPrinter(...arguments);
        }
    },
});
