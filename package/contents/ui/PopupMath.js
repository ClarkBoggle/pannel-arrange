/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure computations for resizing the popup of a panel widget on a grid
// (tested by tests/tst_popupmath.qml).
.pragma library

// Size snapped to a whole number of cells, within [min, max]. Without a grid
// (cell 0 or 1 px), only clamped. When no multiple of the cell fits between
// min and max, the nearest valid size.
function snapSize(size, cell, min, max) {
    const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
    const smallest = Math.ceil(min / cell) * cell;
    const largest = Math.floor(max / cell) * cell;
    if (!(cell > 1) || smallest > largest) {
        return clamp(Math.round(size), min, max);
    }
    return clamp(Math.round(size / cell) * cell, smallest, largest);
}

// Edges of a popup placed by the user along the panel (positions from the start
// of the panel), one of them dragged to rawPosition: the dragged edge snaps to a
// grid line (multiple of cell from the start of the panel), the other stays;
// the size stays within [minSize, maxSize] and the popup within the panel
// (length). Returns { start, end }.
function dragEdge(start, end, movingStart, rawPosition, cell, minSize, maxSize, length) {
    if (movingStart) {
        return { start: snapSize(rawPosition, cell, Math.max(0, end - maxSize), end - minSize), end: end };
    }
    return { start: start, end: snapSize(rawPosition, cell, start + minSize, Math.min(length, start + maxSize)) };
}

// How much the popup size changes when its dragged edge moves by one pixel,
// along the panel: Plasma keeps the popup centered on its widget, so both edges
// move (2), unless the popup is held against the side of its area (1).
// Across the panel, the popup is attached to the panel by one edge (always 1).
function sizeFactor(alongPanel, popupCenter, widgetCenter) {
    return alongPanel && Math.abs(popupCenter - widgetCenter) <= 1 ? 2 : 1;
}

// The edges of the popup that can be dragged: all but the one attached to the
// panel. direction: the side of the widget where the popup opens (Qt.TopEdge:
// above a bottom panel). Edge values are those of Qt.Edge.
function freeEdges(direction) {
    const top = 1, left = 2, right = 4, bottom = 8; // Qt.TopEdge, LeftEdge, RightEdge, BottomEdge
    switch (direction) {
    case top:
        return top | left | right;
    case bottom:
        return bottom | left | right;
    case left:
        return left | top | bottom;
    case right:
        return right | top | bottom;
    default:
        return 0;
    }
}
