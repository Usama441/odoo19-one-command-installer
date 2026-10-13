import { localization } from "@web/core/l10n/localization";

const DEFAULT_MIN_SCALE = 0.2;
const DEFAULT_MAX_SCALE = 2;

/**
 * @param {number} scale
 * @param {number} [min]
 * @param {number} [max]
 * @returns {number}
 */
export function clampScale(scale, min = DEFAULT_MIN_SCALE, max = DEFAULT_MAX_SCALE) {
    const normalizedScale = Number.isFinite(scale) ? scale : 1;
    return Math.min(max, Math.max(min, normalizedScale));
}

/**
 * @param {number} deltaX
 * @returns {number}
 */
export function toInlineDeltaX(deltaX) {
    return localization.direction === "rtl" ? -deltaX : deltaX;
}

/**
 * @param {number} clientX
 * @param {{ left: number, right: number }} canvasRect
 * @returns {number}
 */
export function getInlineOffsetX(clientX, canvasRect) {
    return localization.direction === "rtl"
        ? canvasRect.right - clientX
        : clientX - canvasRect.left;
}

/**
 * Convert screen coordinates into flow world coordinates.
 *
 * @param {{ x: number, y: number }} point
 * @param {{ left: number, right: number, top: number }} canvasRect
 * @param {{ x: number, y: number, scale: number }} viewport
 * @returns {import("../flow_types").FlowPosition}
 */
export function screenToWorld(point, canvasRect, viewport) {
    const scale = clampScale(viewport.scale);
    return {
        x: (getInlineOffsetX(point.x, canvasRect) - viewport.x) / scale,
        y: (point.y - canvasRect.top - viewport.y) / scale,
    };
}

/**
 * Convert flow world coordinates into screen coordinates.
 *
 * @param {import("../flow_types").FlowPosition} point
 * @param {{ left: number, right: number, top: number }} canvasRect
 * @param {{ x: number, y: number, scale: number }} viewport
 * @returns {{ x: number, y: number }}
 */
export function worldToScreen(point, canvasRect, viewport) {
    const scale = clampScale(viewport.scale);
    const inlineOffsetX = viewport.x + point.x * scale;
    return {
        x:
            localization.direction === "rtl"
                ? canvasRect.right - inlineOffsetX
                : canvasRect.left + inlineOffsetX,
        y: canvasRect.top + viewport.y + point.y * scale,
    };
}
