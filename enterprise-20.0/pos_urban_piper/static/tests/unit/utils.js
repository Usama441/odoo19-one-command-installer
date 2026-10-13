import { getFilledOrder } from "@point_of_sale/../tests/unit/utils";
import { serverState } from "@web/../tests/web_test_helpers";

export const deliveryJson = JSON.stringify({
    order: {
        details: {
            created: 1735879045123,
            delivery_datetime: 1735880545123,
            ext_platforms: [
                {
                    id: "TST-1756819673",
                    delivery_type: "partner",
                    name: "DoorDash",
                    extras: { order_otp: "123456" },
                },
            ],
        },
        store: { name: "Main Branch" },
        payment: [{ option: "card" }],
    },
    customer: {
        name: "Monkey D. Luffy",
        phone: "+91 99999 11111",
        email: "future.king@onepiece.com",
        address: {
            line_1: "Thousand sunny",
            line_2: "Near Grand Line, East Blue",
            city: "Windmill Village",
            pin: "000001",
        },
    },
});

export const urbanPiperOrderValues = {
    source: "online",
    delivery_provider_id: 1,
    prep_time: 25.0,
    delivery_identifier: "OID001",
    delivery_json: deliveryJson,
};

export const getUrbanPiperFilledOrder = async (store, data = {}) => {
    const order = await getFilledOrder(store, {
        ...urbanPiperOrderValues,
        ...data,
    });
    order.setPartner(store.models["res.partner"].get(serverState.partnerId));
    order.preset_id = false;
    return order;
};
