import { createPrepDisplayTicket } from "@pos_enterprise/../tests/unit/utils";
import { urbanPiperOrderValues } from "../utils";

/**
 * Create a preparation display ticket for an UrbanPiper delivery order.
 */
export const createUrbanPiperPrepDisplayTicket = async (store, extraOrderFields = {}) =>
    await createPrepDisplayTicket(store, {
        extraOrderFields: {
            ...urbanPiperOrderValues,
            ...extraOrderFields,
            delivery_status: "acknowledged",
        },
    });
