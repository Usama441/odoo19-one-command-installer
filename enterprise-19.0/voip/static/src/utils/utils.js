import { normalize } from "@web/core/l10n/utils";

/**
 * Removes whitespaces, dashes, slashes and periods from a phone number.
 *
 * @param {string} phoneNumber
 * @returns {string}
 */
export function cleanPhoneNumber(phoneNumber) {
    // U+00AD is the “soft hyphen” character
    return phoneNumber.replace(/[-()\s/.\u00AD]/g, "");
}

const editableInputTypes = new Set([
    "date",
    "datetime-local",
    "email",
    "month",
    "number",
    "password",
    "search",
    "tel",
    "text",
    "time",
    "url",
    "week",
]);

/**
 * Determines whether the currently focused element is editable. This is useful
 * for preventing auto-focus mechanisms when the user is already typing
 * elsewhere.
 *
 * @returns {boolean}
 */
export function isCurrentFocusEditable() {
    const el = document.activeElement;
    if (!el) {
        return false;
    }
    if (el.isContentEditable) {
        return true;
    }
    const tag = el.tagName.toLowerCase();
    if (tag === "textarea") {
        return true;
    }
    if (tag === "input") {
        const inputType = el.getAttribute("type")?.toLowerCase() || "text";
        return editableInputTypes.has(inputType);
    }
    return false;
}

export function isSubstring(targetString, substring) {
    if (!targetString) {
        return false;
    }
    return normalize(targetString).includes(normalize(substring));
}
