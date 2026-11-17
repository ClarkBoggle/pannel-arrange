/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "PopupMath.js" as PopupMath

// Resize handles put inside the popup of a panel widget (over its content) while
// the panel is in edit mode: on its free edges and corners, not on the edge
// attached to the panel. The popup size snaps to the plasmoid grid cells while
// dragging. Plasma keeps the popup in place (centered on its widget, against the
// panel) whatever its size: only the size is set here. Plasma saves it when the
// popup closes (popupWidth/popupHeight of the widget).
Item {
    id: handles

    // Plasmoid grid cell of a screen, by its name: { width, height }, or null
    // without a grid (the size is then free)
    required property var cellOn

    signal closed()

    anchors.fill: parent
    z: 1000 // above the widget content

    readonly property var popup: Window.window
    // Side of its widget where the popup opens (Qt.TopEdge: above a bottom panel)
    readonly property int direction: popup?.effectivePopupDirection ?? Qt.TopEdge
    readonly property bool horizontalPanel: direction === Qt.TopEdge || direction === Qt.BottomEdge
    readonly property int freeEdges: PopupMath.freeEdges(direction)

    readonly property int thickness: Kirigami.Units.largeSpacing
    readonly property int cornerSize: thickness * 3

    // While dragging: the size the mouse asks for, not snapped, and the grid
    property bool dragging: false
    property real rawWidth: 0
    property real rawHeight: 0
    property point lastPosition
    property var cell: null

    Connections {
        target: handles.popup
        function onVisibleChanged(): void {
            if (!handles.popup.visible) {
                handles.closed();
            }
        }
    }

    function dragStarted(position: point): void {
        cell = cellOn(handles.Screen.name);
        rawWidth = popup.width;
        rawHeight = popup.height;
        lastPosition = position;
        dragging = true;
    }

    function dragMoved(edges: int, position: point): void {
        const dx = position.x - lastPosition.x;
        const dy = position.y - lastPosition.y;
        lastPosition = position;

        const widget = popup.visualParent;
        const widgetCenter = widget ? widget.mapToGlobal(widget.width / 2, widget.height / 2)
                                    : Qt.point(popup.x + popup.width / 2, popup.y + popup.height / 2);
        if (edges & (Qt.LeftEdge | Qt.RightEdge)) {
            const factor = PopupMath.sizeFactor(horizontalPanel, popup.x + popup.width / 2, widgetCenter.x);
            rawWidth += (edges & Qt.RightEdge ? dx : -dx) * factor;
        }
        if (edges & (Qt.TopEdge | Qt.BottomEdge)) {
            const factor = PopupMath.sizeFactor(!horizontalPanel, popup.y + popup.height / 2, widgetCenter.y);
            rawHeight += (edges & Qt.BottomEdge ? dy : -dy) * factor;
        }

        const width = PopupMath.snapSize(rawWidth, cell?.width ?? 0, popup.minimumWidth, popup.maximumWidth);
        const height = PopupMath.snapSize(rawHeight, cell?.height ?? 0, popup.minimumHeight, popup.maximumHeight);
        if (width !== popup.width) {
            popup.width = width;
        }
        if (height !== popup.height) {
            popup.height = height;
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

    // Size while dragging, in cells (in pixels without a grid)
    Rectangle {
        anchors.centerIn: parent
        visible: handles.dragging
        width: sizeLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
        height: sizeLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.highlightColor

        PlasmaComponents3.Label {
            id: sizeLabel
            anchors.centerIn: parent
            color: Kirigami.Theme.highlightedTextColor
            text: {
                const popup = handles.popup;
                if (!popup) {
                    return "";
                }
                const cell = handles.cell;
                return cell && cell.width > 1 && cell.height > 1
                    ? `${Math.round(popup.width / cell.width)} × ${Math.round(popup.height / cell.height)}`
                    : `${popup.width} × ${popup.height}`;
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

            onPressed: mouse => handles.dragStarted(mapToGlobal(mouse.x, mouse.y))
            onPositionChanged: mouse => {
                if (pressed) {
                    handles.dragMoved(edges, mapToGlobal(mouse.x, mouse.y));
                }
            }
            onReleased: handles.dragging = false
            onCanceled: handles.dragging = false

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
