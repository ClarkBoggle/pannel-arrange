/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure computations used to resize and move popups on a grid.
// Tested by tests/tst_popupmath.qml.
.pragma library

// Qt.Edge values (not available in a library script)
const TOP = 1;
const LEFT = 2;
const RIGHT = 4;
const BOTTOM = 8;

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

// Rounds a size to a whole number of cells, keeping it within [min, max].
// Without a grid (cell of 0 or 1 px) the size is only clamped. If no multiple
// of the cell fits between min and max, returns the closest allowed size.
function snapSize(size, cell, min, max) {
    const smallest = Math.ceil(min / cell) * cell;
    const largest = Math.floor(max / cell) * cell;
    if (!(cell > 1) || smallest > largest) {
        return clamp(Math.round(size), min, max);
    }
    return clamp(Math.round(size / cell) * cell, smallest, largest);
}

// A popup placed along the panel goes from `start` to `end` (pixels from the
// start of the panel). One of its edges is dragged to `rawPosition`: that edge
// snaps to the grid, the other one stays. The size stays within
// [minSize, maxSize] and the popup within the panel (`length`).
// Returns { start, end }.
function dragEdge(start, end, movingStart, rawPosition, cell, minSize, maxSize, length) {
    if (movingStart) {
        return { start: snapSize(rawPosition, cell, Math.max(0, end - maxSize), end - minSize), end: end };
    }
    return { start: start, end: snapSize(rawPosition, cell, start + minSize, Math.min(length, start + maxSize)) };
}

// How much the popup grows when one of its edges moves by one pixel.
// Plasma keeps a popup centered on its widget, so along the panel both edges
// move and the popup grows twice as fast, unless it is pushed against the side
// of the screen (then its center is no longer the widget's). Across the panel,
// one edge is stuck to the panel: always 1.
function sizeFactor(alongPanel, popupCenter, widgetCenter) {
    return alongPanel && Math.abs(popupCenter - widgetCenter) <= 1 ? 2 : 1;
}

// The edges of a popup that can be dragged: all except the one against the
// panel. `direction` is the side of the widget where the popup opens
// (Qt.TopEdge: above a bottom panel).
function freeEdges(direction) {
    switch (direction) {
    case TOP:
        return TOP | LEFT | RIGHT;
    case BOTTOM:
        return BOTTOM | LEFT | RIGHT;
    case LEFT:
        return LEFT | TOP | BOTTOM;
    case RIGHT:
        return RIGHT | TOP | BOTTOM;
    default:
        return 0;
    }
}
