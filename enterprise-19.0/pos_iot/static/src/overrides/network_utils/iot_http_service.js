import { patch } from "@web/core/utils/patch";
import { iotHttpService } from "@iot/network_utils/iot_http_service";

patch(iotHttpService, {
    dependencies: iotHttpService.dependencies.filter((dep) => dep !== "lazy_session"),
});
