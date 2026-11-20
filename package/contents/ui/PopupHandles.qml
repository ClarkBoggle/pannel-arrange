/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

import "PopupMath.js" as PopupMath

// Shown over the content of a widget's popup while the panel is in edit mode:
//
// - resize handles on the free edges and corners (not on the edge against the
//   panel); the size snaps to the plasmoid grid while dragging;
// - in the middle, the size and the position along the panel, in cells;
// - dragging anywhere else moves the popup along the panel, snapped to the
//   cells; a double click puts it back centered on its widget.
//
// A popup that was never moved stays centered on its widget: resizing it moves
// both its edges along the panel. A moved popup keeps its place: only the
// dragged edge moves. Plasma saves the size when the popup closes;
// PopupPlacement saves the position.
Item {
    id: handles

    // Function: screen name → plasmoid grid cell ({ width, height }), or null
    // without a grid (the size is then free)
    required property var cellOn
    required property PopupPlacement placement
    required property Item plasmoidItem

    signal closed()

    anchors.fill: parent
    z: 1000 // above the widget content

    readonly property var popup: Window.window

    // Side of the widget where the popup opens (Qt.TopEdge: above a bottom panel)
    readonly property int direction: popup?.effectivePopupDirection ?? Qt.TopEdge
    readonly property bool horizontalPanel: direction === Qt.TopEdge || direction === Qt.BottomEdge
    readonly property int freeEdges: PopupMath.freeEdges(direction)
    // Moving these edges changes the length of the popup along the panel
    readonly property int alongEdges: horizontalPanel ? (Qt.LeftEdge | Qt.RightEdge) : (Qt.TopEdge | Qt.BottomEdge)

    readonly property int thickness: Kirigami.Units.largeSpacing
    readonly property int cornerSize: thickness * 3

    // Grid cell on the popup's screen, looked up again at each drag
    property var cell: null
    readonly property real cellAlong: (horizontalPanel ? cell?.width : cell?.height) ?? 0
    readonly property real cellAcross: (horizontalPanel ? cell?.height : cell?.width) ?? 0

    // Position while dragging (saved on release), else undefined
    property var liveOffset: undefined
    // Position being dragged or saved; undefined when centered
    readonly property var targetOffset: liveOffset ?? placement.offsets[plasmoidItem?.Plasmoid?.id]
    readonly property bool placed: targetOffset !== undefined

    // Drag state. The raw values follow the mouse, without snapping.
    property bool dragging: false
    property real rawWidth: 0
    property real rawHeight: 0
    property real rawPosition: 0 // dragged edge, or popup start, along the panel
    property real pressStart: 0  // popup start and end along the panel, at the press
    property real pressEnd: 0
    property point lastPosition

    // (the Screen attached property is only known once in the popup)
    Component.onCompleted: Qt.callLater(() => cell = cellOn(handles.Screen.name))

    // Back on the grid when the handles appear, and at each drag (a new cell
    // object each time): a popup sized without the grid, or on another one,
    // would otherwise never get a whole number of cells.
    onCellChanged: fitToGrid()

    Connections {
        target: handles.popup
        function onVisibleChanged(): void {
            if (!handles.popup.visible) {
                handles.closed();
            }
        }
    }

    // ---- Waiting for the popup to move ----
    //
    // On Wayland, mouse positions are relative to the popup, and the popup
    // moves when it is resized or moved. Until the compositor has actually
    // moved it, the positions we receive are relative to its old place and
    // look like a move back: the popup would shake. So mouse moves are ignored
    // for two frames after each change (one frame was measured not to be
    // enough: the compositor moves the popup one frame after resizing it).

    property int settleFrames: 0
    readonly property bool settling: settleFrames > 0
    property real lastFrameTime: 0

    // To call after each change of the popup size or position
    function geometryAsked(): void {
        settleFrames = 2;
        settleTimer.restart();
    }

    Connections {
        target: handles.popup
        function onFrameSwapped(): void {
            // (sometimes emitted twice for the same frame)
            const now = Date.now();
            const sameFrame = now - handles.lastFrameTime < 3;
            handles.lastFrameTime = now;
            if (sameFrame || handles.settleFrames === 0) {
                return;
            }
            handles.settleFrames--;
            if (handles.settleFrames > 0) {
                handles.popup.update(); // ask for the next frame
            }
        }
    }

    // In case no frame comes
    Timer {
        id: settleTimer
        interval: 100
        onTriggered: handles.settleFrames = 0
    }

    // ---- Keeping the popup on the grid ----

    function fitToGrid(): void {
        if (dragging || !popup || !cell) {
            return;
        }
        const width = PopupMath.snapSize(popup.width, cell.width, popup.minimumWidth, popup.maximumWidth);
        const height = PopupMath.snapSize(popup.height, cell.height, popup.minimumHeight, popup.maximumHeight);

        // The position of a moved popup too
        const saved = placement.offsetOf(plasmoidItem);
        const room = placement.panelLength() - (horizontalPanel ? width : height);
        if (saved !== undefined && room >= 0) {
            const offset = PopupMath.snapSize(saved, cellAlong, 0, room);
            if (offset !== saved) {
                placement.setOffset(plasmoidItem, offset, true);
                geometryAsked();
            }
        }
        setLength(width, true);
        setLength(height, false);
    }

    // Plasma grows the popup to the minimum size of its content, which may
    // grow later (e.g. the CPU monitor once its sensors are loaded): back to
    // the first whole number of cells above it.
    Connections {
        target: handles.popup
        function onMinimumWidthChanged(): void {
            Qt.callLater(handles.fitToGrid);
        }
        function onMinimumHeightChanged(): void {
            Qt.callLater(handles.fitToGrid);
        }
    }

    // The popup border (around our handles) still resizes it natively: the
    // compositor does it pixel by pixel, without our grid. Each size it gives
    // is put back on the grid at once, as terminals do with their character
    // cells, and once more when the size stops changing. Both are limited, in
    // case the compositor refuses a size.
    property bool fitting: false
    property int fitBurst: 0
    property real fitBurstTime: 0
    property int fitTries: 0

    Connections {
        target: handles.popup
        function onWidthChanged(): void {
            handles.sizeChanged();
        }
        function onHeightChanged(): void {
            handles.sizeChanged();
        }
    }

    function sizeChanged(): void {
        fitTimer.restart();
        if (fitting || dragging) {
            return;
        }
        // At most 30 fits within 100 ms
        const now = Date.now();
        if (now - fitBurstTime > 100) {
            fitBurstTime = now;
            fitBurst = 0;
        }
        if (++fitBurst > 30) {
            return;
        }
        fitting = true;
        fitToGrid();
        fitting = false;
    }

    Timer {
        id: fitTimer
        interval: 250
        onTriggered: {
            const popup = handles.popup;
            if (handles.dragging || !popup || !handles.cell) {
                return;
            }
            const width = popup.width;
            const height = popup.height;
            // At most 3 tries in a row that change the size
            if (handles.fitTries < 3) {
                handles.fitting = true;
                handles.fitToGrid();
                handles.fitting = false;
            }
            const changed = popup.width !== width || popup.height !== height;
            handles.fitTries = changed ? handles.fitTries + 1 : 0;
        }
    }

    // ---- Dragging ----

    // Length of the popup along the panel
    function length(): real {
        return horizontalPanel ? popup.width : popup.height;
    }

    function setLength(size: real, horizontal: bool): void {
        if (horizontal && size !== popup.width) {
            popup.width = size;
            geometryAsked();
        } else if (!horizontal && size !== popup.height) {
            popup.height = size;
            geometryAsked();
        }
    }

    function dragStarted(position: point): void {
        cell = cellOn(handles.Screen.name);
        rawWidth = popup.width;
        rawHeight = popup.height;
        // A moved popup starts from its saved position, not from its window:
        // the window may not be there yet, or be one pixel off (centered on its
        // anchor with an odd size).
        pressStart = placement.offsetOf(plasmoidItem) ?? placement.currentOffset(popup);
        pressEnd = pressStart + length();
        lastPosition = position;
        fitTries = 0;
        dragging = true;
    }

    function dragEnded(): void {
        dragging = false;
        if (liveOffset !== undefined) {
            placement.setOffset(plasmoidItem, liveOffset, true);
            liveOffset = undefined; // (saved now, and fitToGrid() may change it)
        }
    }

    // Move along the panel

    function moveStarted(position: point): void {
        dragStarted(position);
        rawPosition = pressStart;
    }

    function moveMoved(position: point): void {
        if (settling) {
            return;
        }
        rawPosition += horizontalPanel ? position.x - lastPosition.x : position.y - lastPosition.y;
        lastPosition = position;

        const offset = PopupMath.snapSize(rawPosition, cellAlong, 0, placement.panelLength() - length());
        if (offset !== liveOffset) {
            liveOffset = offset;
            placement.setOffset(plasmoidItem, offset, false);
            geometryAsked();
        }
    }

    // Resize

    function resizeStarted(edges: int, position: point): void {
        dragStarted(position);
        rawPosition = movesStart(edges) ? pressStart : pressEnd;
    }

    function resizeMoved(edges: int, position: point): void {
        if (settling) {
            return;
        }
        const dx = position.x - lastPosition.x;
        const dy = position.y - lastPosition.y;
        lastPosition = position;

        if (edges & alongEdges) {
            if (placed) {
                resizeMovedPopup(edges, horizontalPanel ? dx : dy);
            } else {
                resizeCenteredPopup(edges, horizontalPanel ? dx : dy);
            }
        }
        if (edges & ~alongEdges) {
            resizeAcross(edges, dx, dy);
        }
    }

    // Whether the dragged edges include the start (left or top) of the popup
    // along the panel
    function movesStart(edges: int): bool {
        return (edges & (Qt.LeftEdge | Qt.TopEdge) & alongEdges) !== 0;
    }

    // A moved popup: only the dragged edge moves, snapped to the cells of the
    // panel. The anchor is moved first (see askedLength in PopupPlacement).
    function resizeMovedPopup(edges: int, delta: real): void {
        rawPosition += delta;
        const minimum = horizontalPanel ? popup.minimumWidth : popup.minimumHeight;
        const maximum = horizontalPanel ? popup.maximumWidth : popup.maximumHeight;
        const span = PopupMath.dragEdge(pressStart, pressEnd, movesStart(edges), rawPosition, cellAlong,
                                        minimum, maximum, placement.panelLength());
        const newLength = span.end - span.start;
        if (span.start !== liveOffset || newLength !== length()) {
            liveOffset = span.start;
            placement.setOffset(plasmoidItem, span.start, false, newLength);
            geometryAsked();
        }
        setLength(newLength, horizontalPanel);
    }

    // A popup centered on its widget by Plasma: both edges move
    function resizeCenteredPopup(edges: int, delta: real): void {
        const widget = popup.visualParent;
        const widgetCenter = widget ? widget.mapToGlobal(widget.width / 2, widget.height / 2)
                                    : Qt.point(popup.x + popup.width / 2, popup.y + popup.height / 2);
        const growth = movesStart(edges) ? -delta : delta;
        if (horizontalPanel) {
            rawWidth += growth * PopupMath.sizeFactor(true, popup.x + popup.width / 2, widgetCenter.x);
            setLength(PopupMath.snapSize(rawWidth, cellAlong, popup.minimumWidth, popup.maximumWidth), true);
        } else {
            rawHeight += growth * PopupMath.sizeFactor(true, popup.y + popup.height / 2, widgetCenter.y);
            setLength(PopupMath.snapSize(rawHeight, cellAlong, popup.minimumHeight, popup.maximumHeight), false);
        }
    }

    // Across the panel: the other edge stays against the panel
    function resizeAcross(edges: int, dx: real, dy: real): void {
        if (horizontalPanel) {
            rawHeight += (edges & Qt.BottomEdge) ? dy : -dy;
            setLength(PopupMath.snapSize(rawHeight, cellAcross, popup.minimumHeight, popup.maximumHeight), false);
        } else {
            rawWidth += (edges & Qt.RightEdge) ? dx : -dx;
            setLength(PopupMath.snapSize(rawWidth, cellAcross, popup.minimumWidth, popup.maximumWidth), true);
        }
    }

    // ---- Display ----

    // A number of cells (one decimal if not whole), or pixels without a grid
    function cells(pixels: real, cellSize: real): string {
        if (!(cellSize > 1)) {
            return String(Math.round(pixels));
        }
        const count = pixels / cellSize;
        const whole = Math.abs(count - Math.round(count)) < 0.05;
        return whole ? String(Math.round(count)) : count.toLocaleString(Qt.locale(), "f", 1);
    }

    // Position shown for a centered popup: its window position, but not while
    // it settles (it is then briefly elsewhere). For a moved popup the label
    // shows the asked position instead, for the same reason.
    property real centeredOffset: 0
    Binding {
        target: handles
        property: "centeredOffset"
        when: !handles.placed && !handles.settling && !!handles.popup && !!handles.placement.Window.window
        value: handles.popup ? handles.placement.currentOffset(handles.popup) : 0
        restoreMode: Binding.RestoreNone
    }

    // Moving: drag anywhere except on the handles (the widget content gets
    // no clicks while editing). Double click: back to centered.
    MouseArea {
        id: moveArea
        anchors.fill: parent
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: mouse => handles.moveStarted(mapToGlobal(mouse.x, mouse.y))
        onPositionChanged: mouse => {
            if (pressed) {
                handles.moveMoved(mapToGlobal(mouse.x, mouse.y));
            }
        }
        onReleased: handles.dragEnded()
        onCanceled: handles.dragEnded()
        onDoubleClicked: {
            handles.liveOffset = undefined;
            handles.placement.setOffset(handles.plasmoidItem, undefined, true);
        }
    }

    // Frame showing that the popup can be resized
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Kirigami.Theme.highlightColor
        border.width: 2
        opacity: handles.dragging ? 1 : 0.6
    }

    // Size and position, always shown
    Rectangle {
        anchors.centerIn: parent
        width: infoColumn.implicitWidth + Kirigami.Units.largeSpacing * 2
        height: infoColumn.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.highlightColor
        opacity: handles.dragging ? 1 : 0.8

        Column {
            id: infoColumn
            anchors.centerIn: parent

            PlasmaComponents3.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Kirigami.Theme.highlightedTextColor
                text: {
                    const popup = handles.popup;
                    if (!popup) {
                        return "";
                    }
                    const width = handles.cells(popup.width, handles.cell?.width ?? 0);
                    const height = handles.cells(popup.height, handles.cell?.height ?? 0);
                    return `${width} × ${height}`;
                }
            }
            PlasmaComponents3.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Kirigami.Theme.highlightedTextColor
                text: {
                    if (!handles.popup || !handles.placement.Window.window) {
                        return "";
                    }
                    const offset = handles.targetOffset ?? handles.centeredOffset;
                    return `${handles.horizontalPanel ? "x" : "y"} ${handles.cells(offset, handles.cellAlong)}`;
                }
            }
        }
    }

    // Resize handles: the 4 sides and the 4 corners, those that are free
    Repeater {
        model: [Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge, Qt.RightEdge,
                Qt.TopEdge | Qt.LeftEdge, Qt.TopEdge | Qt.RightEdge,
                Qt.BottomEdge | Qt.LeftEdge, Qt.BottomEdge | Qt.RightEdge]
            .filter(edges => (edges & ~handles.freeEdges) === 0)

        delegate: MouseArea {
            id: handle

            // The edges this handle moves
            required property int modelData
            readonly property int edges: modelData
            readonly property bool corner: (edges & (Qt.LeftEdge | Qt.RightEdge)) && (edges & (Qt.TopEdge | Qt.BottomEdge))
            readonly property bool verticalSide: edges === Qt.LeftEdge || edges === Qt.RightEdge

            x: (edges & Qt.RightEdge) ? handles.width - width
               : (edges & Qt.LeftEdge) ? 0 : handles.cornerSize
            y: (edges & Qt.BottomEdge) ? handles.height - height
               : (edges & Qt.TopEdge) ? 0 : handles.cornerSize
            width: corner ? handles.cornerSize
                   : verticalSide ? handles.thickness : handles.width - handles.cornerSize * 2
            height: corner ? handles.cornerSize
                    : verticalSide ? handles.height - handles.cornerSize * 2 : handles.thickness

            hoverEnabled: true
            preventStealing: true
            cursorShape: {
                if (!corner) {
                    return verticalSide ? Qt.SizeHorCursor : Qt.SizeVerCursor;
                }
                const backslash = edges === (Qt.TopEdge | Qt.LeftEdge) || edges === (Qt.BottomEdge | Qt.RightEdge);
                return backslash ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
            }

            onPressed: mouse => handles.resizeStarted(edges, mapToGlobal(mouse.x, mouse.y))
            onPositionChanged: mouse => {
                if (pressed) {
                    handles.resizeMoved(edges, mapToGlobal(mouse.x, mouse.y));
                }
            }
            onReleased: handles.dragEnded()
            onCanceled: handles.dragEnded()

            // Grip: a bar in the middle of a side, a dot in a corner
            Rectangle {
                anchors.centerIn: parent
                width: handle.corner ? handles.thickness
                       : handle.verticalSide ? handles.thickness / 2 : Kirigami.Units.gridUnit * 2
                height: handle.corner ? handles.thickness
                        : handle.verticalSide ? Kirigami.Units.gridUnit * 2 : handles.thickness / 2
                radius: Math.min(width, height) / 2
                color: Kirigami.Theme.highlightColor
                opacity: handle.containsMouse || handle.pressed ? 1 : 0.7
            }
        }
    }
}
