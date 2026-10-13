import { advanceTime, beforeEach, expect, test, tick } from "@odoo/hoot";
import { Component, xml } from "@odoo/owl";
import {
    destroyApp,
    mockService,
    mountWithCleanup,
    onRpc,
    patchWithCleanup,
} from "@web/../tests/web_test_helpers";
import { session } from "@web/session";
import { Geolocation } from "@web_enterprise/core/utils/geolocation";

const MAP_BOX_TOKEN = "token";

async function mountGeolocation() {
    let geolocation;
    class Parent extends Component {
        static template = xml``;
        setup() {
            geolocation = new Geolocation();
        }
    }
    await mountWithCleanup(Parent);
    return geolocation;
}

function makeCoordinates(count) {
    return Array.from({ length: count }, (_, i) => ({
        latitude: 10 + i * 0.01,
        longitude: 10 + i * 0.01,
    }));
}

beforeEach(() => {
    patchWithCleanup(session, { map_box_token: MAP_BOX_TOKEN });
});

test("fetchRoute enforces the MapBox coordinate limit for each routing profile", async () => {
    mockService("notification", {
        add(message, options) {
            expect.step(`notification: ${message}`);
            expect(options).toEqual({ type: "warning" });
        },
    });
    onRpc("https://api.mapbox.com/*", () => {
        expect.step("mapbox request");
        return { trips: [{ id: "trip" }], routes: [{ id: "route" }] };
    });

    const geolocation = await mountGeolocation();

    // The optimization API is limited to 12 addresses.
    expect(await geolocation.fetchRoute(makeCoordinates(13), "optimized")).toBe(null);
    expect.verifySteps(["notification: Routing is limited to 12 addresses"]);

    // The directions API handles more: 13 addresses go through without warning.
    expect(await geolocation.fetchRoute(makeCoordinates(13), "ordered")).toEqual({ id: "route" });
    expect.verifySteps(["mapbox request"]);

    // ...but the directions API still bails out above 25 addresses.
    expect(await geolocation.fetchRoute(makeCoordinates(26), "ordered")).toBe(null);
    expect.verifySteps(["notification: Routing is limited to 25 addresses"]);
});

test("fetchRoute does not request MapBox when there is no route to compute", async () => {
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation.fetchRoute(makeCoordinates(3), "disabled")).toBe(null);
    expect(await geolocation.fetchRoute(makeCoordinates(1))).toBe(null);
    geolocation.useMapBoxAPI = false;
    expect(await geolocation.fetchRoute(makeCoordinates(3))).toBe(null);
    expect.verifySteps([]);
});

test("fetchRoute uses the optimization API for optimized routes and the directions API otherwise", async () => {
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
        return { trips: [{ id: "trip" }], routes: [{ id: "route" }] };
    });

    const geolocation = await mountGeolocation();
    const coordinates = [
        { latitude: 50, longitude: 4 },
        { latitude: 51, longitude: 5 },
    ];

    expect(await geolocation.fetchRoute(coordinates, "optimized")).toEqual({ id: "trip" });
    expect(await geolocation.fetchRoute(coordinates, "ordered")).toEqual({ id: "route" });
    expect.verifySteps([
        "https://api.mapbox.com/optimized-trips/v1/mapbox/driving/4,50;5,51?access_token=token&roundtrip=false&steps=true&geometries=geojson&source=first&destination=last",
        "https://api.mapbox.com/directions/v5/mapbox/driving/4,50;5,51?access_token=token&steps=true&geometries=geojson",
    ]);
});

test("fetchRoute warns when MapBox answers with an error message", async () => {
    mockService("notification", {
        add(message, options) {
            expect.step(`notification: ${message}`);
            expect(options).toEqual({ type: "warning" });
        },
    });
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
        return { message: "Route exceeds maximum distance limitation" };
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation.fetchRoute(makeCoordinates(2))).toBe(null);
    expect.verifySteps([
        "https://api.mapbox.com/optimized-trips/v1/mapbox/driving/10,10;10.01,10.01?access_token=token&roundtrip=false&steps=true&geometries=geojson&source=first&destination=last",
        "notification: Route exceeds maximum distance limitation",
    ]);
});

test("geolocatePartners caches the coordinates even if its owner is destroyed", async () => {
    const requestDeferred = Promise.withResolvers();
    onRpc("https://api.mapbox.com/*", async () => {
        expect.step("mapbox request");
        await requestDeferred.promise;
        return { features: [{ place_name: "Grand-Rosière", geometry: { coordinates: [4, 50] } }] };
    });
    onRpc("res.partner", "update_latitude_longitude", ({ args }) => {
        expect.step("update_latitude_longitude");
        expect(args[0]).toEqual([
            {
                id: 1,
                contact_address_complete: "Grand-Rosière",
                partner_latitude: 50,
                partner_longitude: 4,
            },
        ]);
        return true;
    });

    const geolocation = await mountGeolocation();
    const partner = { id: 1, contact_address_complete: "Grand-Rosière" };
    const geolocated = geolocation.geolocatePartners(partner);
    expect.verifySteps(["mapbox request"]);

    // The owner is destroyed (e.g. switching to another view) before the provider answers.
    destroyApp();
    requestDeferred.resolve();
    await geolocated;

    await expect.waitForSteps(["update_latitude_longitude"]);
});

test("geolocatePartners requests each address once and only for partners to locate", async () => {
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
        return { features: [{ place_name: "Somewhere", geometry: { coordinates: [4, 50] } }] };
    });
    onRpc("res.partner", "update_latitude_longitude", ({ args }) => {
        expect.step(`update_latitude_longitude: ${args[0].map((partner) => partner.id)}`);
        return true;
    });

    const geolocation = await mountGeolocation();
    await geolocation.geolocatePartners(
        [
            // same address: requested only once
            { id: 1, contact_address_complete: "A" },
            { id: 2, contact_address_complete: "A" },
            // valid coordinates: not requested
            { id: 3, contact_address_complete: "B", partner_latitude: 51, partner_longitude: 5 },
            // invalid coordinates: requested again
            { id: 4, contact_address_complete: "C", partner_latitude: 100, partner_longitude: 5 },
            // nothing to request, but still counted as processed
            { id: 5, contact_address_complete: "" },
        ],
        () => expect.step("partner processed")
    );

    await expect.waitForSteps([
        "partner processed",
        "https://api.mapbox.com/geocoding/v5/mapbox.places/A.json?access_token=token&cachebuster=1552314159970&autocomplete=true",
        "https://api.mapbox.com/geocoding/v5/mapbox.places/C.json?access_token=token&cachebuster=1552314159970&autocomplete=true",
        "partner processed",
        "partner processed",
        "update_latitude_longitude: 1,2,4",
    ]);
});

test("geolocatePartners does not write partners for which no coordinates were found", async () => {
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
        return { features: [] };
    });
    onRpc("res.partner", "update_latitude_longitude", () => {
        expect.step("update_latitude_longitude");
    });

    const geolocation = await mountGeolocation();
    const partner = { id: 1, contact_address_complete: "Nowhere" };
    await geolocation.geolocatePartners(partner);

    expect.verifySteps([
        "https://api.mapbox.com/geocoding/v5/mapbox.places/Nowhere.json?access_token=token&cachebuster=1552314159970&autocomplete=true",
    ]);
    expect(partner.partner_latitude).toBe(undefined);
    expect(partner.partner_longitude).toBe(undefined);
});

test("_fetchCoordinatesFromAddressMB converts an address into coordinates", async () => {
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
        return {
            features: [{ place_name: "Grand-Rosière", geometry: { coordinates: ["4.1", "50.2"] } }],
        };
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchCoordinatesFromAddressMB("Grand-Rosière")).toEqual([
        { address: "Grand-Rosière", latitude: 50.2, longitude: 4.1 },
    ]);
    expect.verifySteps([
        "https://api.mapbox.com/geocoding/v5/mapbox.places/Grand-Rosi%C3%A8re.json?access_token=token&cachebuster=1552314159970&autocomplete=true",
    ]);
});

test("_fetchCoordinatesFromAddressOSM converts an address into coordinates", async () => {
    onRpc("https://nominatim.openstreetmap.org/*", (request) => {
        expect.step(request.url);
        return [{ display_name: "Grand-Rosière", lat: "50.2", lon: "4.1" }];
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchCoordinatesFromAddressOSM("Grand-Rosière")).toEqual([
        { address: "Grand-Rosière", latitude: 50.2, longitude: 4.1 },
    ]);
    expect.verifySteps([
        "https://nominatim.openstreetmap.org/search?q=Grand-Rosi%C3%A8re&format=jsonv2",
    ]);
});

test("_fetchCoordinatesFromAddressOSM no longer requests OpenStreetMap after a failure", async () => {
    mockService("notification", {
        add(message) {
            expect.step(`notification: ${message}`);
        },
    });
    onRpc("https://nominatim.openstreetmap.org/*", (request) => {
        expect.step(request.url);
        throw new Error("Too Many Requests");
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchCoordinatesFromAddressOSM("A")).toEqual([]);
    expect.verifySteps([
        "https://nominatim.openstreetmap.org/search?q=A&format=jsonv2",
        "notification: OpenStreetMap's request limit exceeded, try again later.",
    ]);

    expect(await geolocation._fetchCoordinatesFromAddressOSM("B")).toEqual([]);
    expect.verifySteps([]);
});

test("_fetchAddressFromCoordinatesMB converts coordinates into an address", async () => {
    onRpc("https://api.mapbox.com/*", (request) => {
        expect.step(request.url);
        return {
            features: [
                { place_type: ["address"], text: "Sweet Street", address: "12" },
                { place_type: ["place"], text: "Somewhere" },
                { place_type: ["postcode"], text: "1000" },
                { place_type: ["region"], text: "Brussels" },
                { place_type: ["country"], text: "Belgium" },
            ],
        };
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchAddressFromCoordinatesMB(50.85, 4.35)).toEqual({
        street: "Sweet Street",
        house_number: "12",
        city: "Somewhere",
        zip: "1000",
        state: "Brussels",
        country: "Belgium",
    });
    expect.verifySteps([
        "https://api.mapbox.com/geocoding/v5/mapbox.places/4.35,50.85.json?access_token=token&cachebuster=1552314159970&types=address,place,postcode,region,country",
    ]);
});

test("_fetchAddressFromCoordinatesMB picks each field by its place_type, regardless of the features' order or a missing one", async () => {
    onRpc("https://api.mapbox.com/geocoding/v5/*", () => {
        expect.step("mapbox geocoding request");
        return {
            features: [
                // Deliberately out of the usual [address, place, postcode, region, country] order,
                // and missing a "region" feature entirely (e.g. no state/province at these coordinates).
                { place_type: ["country"], text: "Belgium" },
                { place_type: ["postcode"], text: "1000" },
                { place_type: ["address"], text: "Sweet Street", address: "12" },
                { place_type: ["place"], text: "Somewhere" },
            ],
        };
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchAddressFromCoordinatesMB(38.71, -9.14)).toEqual({
        street: "Sweet Street",
        house_number: "12",
        city: "Somewhere",
        zip: "1000",
        state: undefined,
        country: "Belgium",
    });
    expect.verifySteps(["mapbox geocoding request"]);
});

test("_fetchAddressFromCoordinatesOSM converts coordinates into an address", async () => {
    onRpc("https://nominatim.openstreetmap.org/*", (request) => {
        expect.step(request.url);
        return {
            address: {
                road: "Sweet Street",
                house_number: "12",
                city: "Somewhere",
                postcode: "1000",
                state: "Brussels",
                country: "Belgium",
            },
        };
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchAddressFromCoordinatesOSM(50.85, 4.35)).toEqual({
        street: "Sweet Street",
        house_number: "12",
        city: "Somewhere",
        zip: "1000",
        state: "Brussels",
        country: "Belgium",
    });
    expect.verifySteps([
        "https://nominatim.openstreetmap.org/reverse?lat=50.85&lon=4.35&format=jsonv2",
    ]);
});

test("_fetchAddressFromCoordinatesOSM no longer requests OpenStreetMap after a failure", async () => {
    mockService("notification", {
        add(message) {
            expect.step(`notification: ${message}`);
        },
    });
    onRpc("https://nominatim.openstreetmap.org/*", (request) => {
        expect.step(request.url);
        throw new Error("Too Many Requests");
    });

    const geolocation = await mountGeolocation();

    expect(await geolocation._fetchAddressFromCoordinatesOSM(50.85, 4.35)).toEqual({});
    expect.verifySteps([
        "https://nominatim.openstreetmap.org/reverse?lat=50.85&lon=4.35&format=jsonv2",
        "notification: OpenStreetMap's request limit exceeded, try again later.",
    ]);

    expect(await geolocation._fetchAddressFromCoordinatesOSM(40.21, 5.65)).toEqual({});
    expect.verifySteps([]);
});

test("searchCoordinatesFromAddress uses MapBox when a token is set", async () => {
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchCoordinatesFromAddressMB(address) {
            expect.step(`mapbox: ${address}`);
            return [];
        },
        async _fetchCoordinatesFromAddressOSM(address) {
            expect.step(`osm: ${address}`);
            return [];
        },
    });

    await geolocation.searchCoordinatesFromAddress("A");
    expect.verifySteps(["mapbox: A"]);
});

test("searchCoordinatesFromAddress uses OpenStreetMap without token", async () => {
    patchWithCleanup(session, { map_box_token: "" });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchCoordinatesFromAddressMB(address) {
            expect.step(`mapbox: ${address}`);
            return [];
        },
        async _fetchCoordinatesFromAddressOSM(address) {
            expect.step(`osm: ${address}`);
            return [];
        },
    });

    await geolocation.searchCoordinatesFromAddress("A");
    expect.verifySteps(["osm: A"]);
});

test("searchCoordinatesFromAddress switches to OpenStreetMap once MapBox failed", async () => {
    mockService("http", {
        get: () => Promise.reject({ status: 401 }),
    });
    mockService("notification", {
        add(message, options) {
            expect.step(`notification: ${options.title}`);
        },
    });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        // not stubbed: the real MapBox call is the one handling the failure and disabling MapBox
        _fetchCoordinatesFromAddressMB(address) {
            expect.step(`mapbox: ${address}`);
            return super._fetchCoordinatesFromAddressMB(address);
        },
        async _fetchCoordinatesFromAddressOSM(address) {
            expect.step(`osm: ${address}`);
            return [];
        },
    });

    expect(await geolocation.searchCoordinatesFromAddress("A")).toEqual([]);
    expect.verifySteps(["mapbox: A", "notification: Token invalid"]);

    await geolocation.searchCoordinatesFromAddress("B");
    expect.verifySteps(["osm: B"]);
});

test("searchAddressFromCoordinates uses MapBox when a token is set", async () => {
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchAddressFromCoordinatesMB(lat, lon) {
            expect.step(`mapbox: ${lat},${lon}`);
            return {};
        },
        async _fetchAddressFromCoordinatesOSM(lat, lon) {
            expect.step(`osm: ${lat},${lon}`);
            return {};
        },
    });

    await geolocation.searchAddressFromCoordinates(50.85, 4.35);
    expect.verifySteps(["mapbox: 50.85,4.35"]);
});

test("searchAddressFromCoordinates uses OpenStreetMap without token", async () => {
    patchWithCleanup(session, { map_box_token: "" });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchAddressFromCoordinatesMB(lat, lon) {
            expect.step(`mapbox: ${lat},${lon}`);
            return {};
        },
        async _fetchAddressFromCoordinatesOSM(lat, lon) {
            expect.step(`osm: ${lat},${lon}`);
            return {};
        },
    });

    await geolocation.searchAddressFromCoordinates(50.85, 4.35);
    expect.verifySteps(["osm: 50.85,4.35"]);
});

test("searchAddressFromCoordinates switches to OpenStreetMap once MapBox failed", async () => {
    mockService("http", {
        get: () => Promise.reject({ status: 500 }),
    });
    mockService("notification", {
        add(message, options) {
            expect.step(`notification: ${options.title}`);
        },
    });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        // not stubbed: the real MapBox call is the one handling the failure and disabling MapBox
        _fetchAddressFromCoordinatesMB(lat, lon) {
            expect.step(`mapbox: ${lat},${lon}`);
            return super._fetchAddressFromCoordinatesMB(lat, lon);
        },
        async _fetchAddressFromCoordinatesOSM(lat, lon) {
            expect.step(`osm: ${lat},${lon}`);
            return {};
        },
    });

    expect(await geolocation.searchAddressFromCoordinates(50.85, 4.35)).toEqual({});
    expect.verifySteps(["mapbox: 50.85,4.35", "notification: MapBox servers unreachable"]);

    await geolocation.searchAddressFromCoordinates(51.2, 4.4);
    expect.verifySteps(["osm: 51.2,4.4"]);
});

test("OpenStreetMap requests are sent once per second", async () => {
    patchWithCleanup(session, { map_box_token: "" });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchCoordinatesFromAddressOSM(address) {
            expect.step(address);
            return [];
        },
    });

    geolocation.searchCoordinatesFromAddress("A");
    geolocation.searchCoordinatesFromAddress("B");
    geolocation.searchCoordinatesFromAddress("C");

    await tick();
    expect.verifySteps(["A"]);
    await advanceTime(1000);
    expect.verifySteps(["B"]);
    await advanceTime(1000);
    expect.verifySteps(["C"]);
});

test("stopFetchingCoordinates drops the OpenStreetMap requests left in the queue", async () => {
    patchWithCleanup(session, { map_box_token: "" });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchCoordinatesFromAddressOSM(address) {
            expect.step(address);
            return [];
        },
    });

    geolocation.searchCoordinatesFromAddress("A");
    geolocation.searchCoordinatesFromAddress("B");
    geolocation.searchCoordinatesFromAddress("C");
    await tick();
    expect.verifySteps(["A"]);

    geolocation.stopFetchingCoordinates();
    await advanceTime(2000);
    expect.verifySteps([]);
});

test("OpenStreetMap requests queued right after stopFetchingCoordinates are still sent once per second", async () => {
    patchWithCleanup(session, { map_box_token: "" });
    const geolocation = await mountGeolocation();
    patchWithCleanup(geolocation, {
        async _fetchCoordinatesFromAddressOSM(address) {
            expect.step(address);
            return [];
        },
    });

    geolocation.searchCoordinatesFromAddress("A");
    geolocation.searchCoordinatesFromAddress("B");
    await tick();
    expect.verifySteps(["A"]);

    geolocation.stopFetchingCoordinates();
    await advanceTime(200);
    geolocation.searchCoordinatesFromAddress("X");
    geolocation.searchCoordinatesFromAddress("Y");
    geolocation.searchCoordinatesFromAddress("Z");
    await advanceTime(800);
    expect.verifySteps(["X"]);
    await advanceTime(1000);
    expect.verifySteps(["Y"]);
    await advanceTime(1000);
    expect.verifySteps(["Z"]);
});
