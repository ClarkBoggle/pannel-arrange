/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

import "PopupMath.js" as PopupMath

// Handles put inside the popup of a panel widget (over its content) while the
// panel is in edit mode:
//
// - Resize handles on its free edges and corners (not on the edge attached to
//   the panel). The size snaps to the plasmoid grid cells while dragging.
// - In the middle, its size and its position along the panel (from the start
//   of the panel), in cells.
// - Dragging anywhere else moves the popup along the panel, snapped to the
//   cells; a double click puts it back centered on its widget.
//
// A popup never moved stays centered on its widget by Plasma: resizing it moves
// both its edges along the panel. A moved popup (PopupPlacement) keeps its
// position: only the dragged edge moves, snapped to the cells of the panel.
// Plasma saves the size when the popup closes (popupWidth/popupHeight of the
// widget); PopupPlacement saves the position.
Item {
    id: handles

    // Plasmoid grid cell of a screen, by its name: { width, height }, or null
    // without a grid (the size is then free)
    required property var cellOn
    required property PopupPlacement placement
    // The widget of the popup
    required property Item plasmoidItem

    signal closed()

    anchors.fill: parent
    z: 1000 // above the widget content

    readonly property var popup: Window.window
    // Side of its widget where the popup opens (Qt.TopEdge: above a bottom panel)
    readonly property int direction: popup?.effectivePopupDirection ?? Qt.TopEdge
    readonly property bool horizontalPanel: direction === Qt.TopEdge || direction === Qt.BottomEdge
    readonly property int freeEdges: PopupMath.freeEdges(direction)
    // Edges along the panel (moving them changes the popup length along it)
    readonly property int alongEdges: horizontalPanel ? (Qt.LeftEdge | Qt.RightEdge) : (Qt.TopEdge | Qt.BottomEdge)

    readonly property int thickness: Kirigami.Units.largeSpacing
    readonly property int cornerSize: thickness * 3

    // Plasmoid grid cell of the screen of the popup (looked up again at each drag)
    property var cell: null
    readonly property real cellAlong: (horizontalPanel ? cell?.width : cell?.height) ?? 0
    readonly property real cellAcross: (horizontalPanel ? cell?.height : cell?.width) ?? 0

    // Position set while dragging (saved on release), undefined when not moved
    // in this session
    property var liveOffset: undefined
    readonly property bool placed: liveOffset !== undefined
        || placement.offsets[plasmoidItem?.Plasmoid.id] !== undefined

    // While dragging: the size or position the mouse asks for, not snapped
    property bool dragging: false
    property real rawWidth: 0
    property real rawHeight: 0
    property real rawPosition: 0 // moved edge or popup start, along the panel
    property real pressStart: 0 // popup start and end along the panel at the press
    property real pressEnd: 0
    property point lastPosition

    // (Screen is only known once in the popup)
    Component.onCompleted: Qt.callLater(() => cell = cellOn(handles.Screen.name))

    // Plasma enlarges the popup to the minimum size of its content, which may
    // grow after the size was set (e.g. the CPU monitor once its sensors are
    // loaded): the size is put back on the grid, on the first whole number of
    // cells above that minimum
    Connections {
        target: handles.popup
        function onMinimumWidthChanged(): void {
            Qt.callLater(handles.fitToGrid);
        }
        function onMinimumHeightChanged(): void {
            Qt.callLater(handles.fitToGrid);
        }
    }

    function fitToGrid(): void {
        if (dragging || !popup || !cell) {
            return;
        }
        setLength(PopupMath.snapSize(popup.width, cell.width, popup.minimumWidth, popup.maximumWidth), true);
        setLength(PopupMath.snapSize(popup.height, cell.height, popup.minimumHeight, popup.maximumHeight), false);
    }

    Connections {
        target: handles.popup
        function onVisibleChanged(): void {
            if (!handles.popup.visible) {
                handles.closed();
            }
        }
    }

    function length(): real {
        return horizontalPanel ? popup.width : popup.height;
    }

    function dragStarted(position: point): void {
        cell = cellOn(handles.Screen.name);
        rawWidth = popup.width;
        rawHeight = popup.height;
        pressStart = placement.currentOffset(popup);
        pressEnd = pressStart + length();
        lastPosition = position;
        dragging = true;
    }

    function dragEnded(): void {
        dragging = false;
        if (liveOffset !== undefined) {
            placement.setOffset(plasmoidItem, liveOffset, true);
        }
    }

    // Move of the popup along the panel, by the middle
    function moveStarted(position: point): void {
        dragStarted(position);
        rawPosition = pressStart;
    }

    function moveMoved(position: point): void {
        rawPosition += horizontalPanel ? position.x - lastPosition.x : position.y - lastPosition.y;
        lastPosition = position;
        const offset = PopupMath.snapSize(rawPosition, cellAlong, 0, placement.panelLength() - length());
        if (offset !== liveOffset) {
            liveOffset = offset;
            placement.setOffset(plasmoidItem, offset, false);
        }
    }

    function resizeStarted(edges: int, position: point): void {
        dragStarted(position);
        rawPosition = (edges & (Qt.LeftEdge | Qt.TopEdge) & alongEdges) ? pressStart : pressEnd;
    }

    function resizeMoved(edges: int, position: point): void {
        const dx = position.x - lastPosition.x;
        const dy = position.y - lastPosition.y;
        lastPosition = position;

        // Along the panel
        if (edges & alongEdges) {
            const delta = horizontalPanel ? dx : dy;
            if (placed) {
                // Only the dragged edge moves, snapped to the cells of the panel
                const movingStart = (edges & (Qt.LeftEdge | Qt.TopEdge) & alongEdges) !== 0;
                rawPosition += delta;
                const minimum = horizontalPanel ? popup.minimumWidth : popup.minimumHeight;
                const maximum = horizontalPanel ? popup.maximumWidth : popup.maximumHeight;
                const span = PopupMath.dragEdge(pressStart, pressEnd, movingStart, rawPosition, cellAlong,
                                                minimum, maximum, placement.panelLength());
                setLength(span.end - span.start, horizontalPanel);
                if (span.start !== liveOffset) {
                    liveOffset = span.start;
                    placement.setOffset(plasmoidItem, span.start, false);
                }
            } else {
                // Centered on its widget by Plasma: both edges move
                const widget = popup.visualParent;
                const widgetCenter = widget ? widget.mapToGlobal(widget.width / 2, widget.height / 2)
                                            : Qt.point(popup.x + popup.width / 2, popup.y + popup.height / 2);
                const movingStart = (edges & (Qt.LeftEdge | Qt.TopEdge) & alongEdges) !== 0;
                if (horizontalPanel) {
                    rawWidth += (movingStart ? -dx : dx) * PopupMath.sizeFactor(true, popup.x + popup.width / 2, widgetCenter.x);
                    setLength(PopupMath.snapSize(rawWidth, cellAlong, popup.minimumWidth, popup.maximumWidth), true);
                } else {
                    rawHeight += (movingStart ? -dy : dy) * PopupMath.sizeFactor(true, popup.y + popup.height / 2, widgetCenter.y);
                    setLength(PopupMath.snapSize(rawHeight, cellAlong, popup.minimumHeight, popup.maximumHeight), false);
                }
            }
        }

        // Across the panel: the popup is attached to the panel by its other edge
        if (edges & ~alongEdges) {
            if (horizontalPanel) {
                rawHeight += (edges & Qt.BottomEdge) ? dy : -dy;
                setLength(PopupMath.snapSize(rawHeight, cellAcross, popup.minimumHeight, popup.maximumHeight), false);
            } else {
                rawWidth += (edges & Qt.RightEdge) ? dx : -dx;
                setLength(PopupMath.snapSize(rawWidth, cellAcross, popup.minimumWidth, popup.maximumWidth), true);
            }
        }
    }

    function setLength(size: real, horizontal: bool): void {
        if (horizontal && size !== popup.width) {
            popup.width = size;
        } else if (!horizontal && size !== popup.height) {
            popup.height = size;
        }
    }

    // Number of cells (one decimal when not whole), or pixels without a grid
    function cells(pixels: real, cellSize: real): string {
        if (!(cellSize > 1)) {
            return String(Math.round(pixels));
        }
        const count = pixels / cellSize;
        return Math.abs(count - Math.round(count)) < 0.05 ? String(Math.round(count))
                                                          : count.toLocaleString(Qt.locale(), "f", 1);
    }

    // Move along the panel: drag anywhere in the popup but on the handles (the
    // widget content gets no clicks while editing); double click: back to
    // centered on its widget
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

    // Size and position, shown all along (user's choice)
    Rectangle {
        id: info
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
                    const cell = handles.cell;
                    return `${handles.cells(popup.width, cell?.width ?? 0)} × ${handles.cells(popup.height, cell?.height ?? 0)}`;
                }
            }
            PlasmaComponents3.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Kirigami.Theme.highlightedTextColor
                text: {
                    const popup = handles.popup;
                    if (!popup || !handles.placement.Window.window) {
                        return "";
                    }
                    const offset = handles.placement.currentOffset(popup);
                    return `${handles.horizontalPanel ? "x" : "y"} ${handles.cells(offset, handles.cellAlong)}`;
                }
            }
        }
    }

    Repeater {
        // Edges moved by each handle: 4 sides, then 4 corners
        model: [Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge, Qt.RightEdge,
                Qt.TopEdge | Qt.LeftEdge, Qt.TopEdge | Qt.RightEdge,
                Qt.BottomEdge | Qt.LeftEdge, Qt.BottomEdge | Qt.RightEdge]
            .filter(edges => (edges & ~handles.freeEdges) === 0)

        delegate: MouseArea {
            id: handle

            required property int modelData
            readonly property int edges: modelData
            readonly property bool corner: (edges & (Qt.LeftEdge | Qt.RightEdge)) && (edges & (Qt.TopEdge | Qt.BottomEdge))
            readonly property bool sideX: edges === Qt.LeftEdge || edges === Qt.RightEdge // left or right side

            x: (edges & Qt.RightEdge) ? handles.width - width
               : (edges & Qt.LeftEdge) ? 0 : handles.cornerSize
            y: (edges & Qt.BottomEdge) ? handles.height - height
               : (edges & Qt.TopEdge) ? 0 : handles.cornerSize
            width: corner ? handles.cornerSize
                   : sideX ? handles.thickness : handles.width - handles.cornerSize * 2
            height: corner ? handles.cornerSize
                    : sideX ? handles.height - handles.cornerSize * 2 : handles.thickness

            hoverEnabled: true
            preventStealing: true
            cursorShape: corner
                ? (edges === (Qt.TopEdge | Qt.LeftEdge) || edges === (Qt.BottomEdge | Qt.RightEdge) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                : (sideX ? Qt.SizeHorCursor : Qt.SizeVerCursor)

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
                width: handle.corner ? handles.thickness : (handle.sideX ? handles.thickness / 2 : Kirigami.Units.gridUnit * 2)
                height: handle.corner ? handles.thickness : (handle.sideX ? Kirigami.Units.gridUnit * 2 : handles.thickness / 2)
                radius: Math.min(width, height) / 2
                color: Kirigami.Theme.highlightColor
                opacity: handle.containsMouse || handle.pressed ? 1 : 0.7
            }
        }
    }
}
