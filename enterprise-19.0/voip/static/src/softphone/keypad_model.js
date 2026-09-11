export class KeypadModel {
    input = {
        value: "",
        selection: {
            start: 0,
            end: 0,
            direction: "none",
        },
        focus: false,
        countryCode: { iso: "", itu: "" },
    };
    showMore = false;

    constructor({ value = "" } = {}) {
        this.value = value;
    }

    reset() {
        Object.assign(this, new KeypadModel());
    }
}
