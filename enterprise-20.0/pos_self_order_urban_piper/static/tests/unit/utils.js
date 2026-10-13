import { unpatchSelf } from "@pos_self_order/app/plugins/pos_data_plugin";
import { setupPosEnvForPrepDisplay } from "@pos_enterprise/../tests/unit/utils";

export const setupPoSEnvForSelfOrderUrbanPiper = async () => {
    unpatchSelf();
    return await setupPosEnvForPrepDisplay();
};
