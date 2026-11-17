/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.plasmoid

// Popups placed by the user along the panel (always, not only in edit mode).
//
// Plasma places a popup centered on its "visual parent" (the widget in the
// panel), against the panel, and places it again at each resize: it cannot be
// moved directly. A popup placed by the user gets an invisible anchor instead,
// in the panel window, centered where the popup must be: Plasma then puts it
// there itself. Its position is the one of its start (left or top edge) from
// the start of the panel window, saved by applet id in PopupOffsets.
//
// Moving a popup is done by PopupHandles (edit mode), through setOffset().
Item {
    id: placement

    // Items of the panel: { applet } (PlasmoidItem or placeholder)
    required property ListModel appletsModel
    required property bool horizontal

    // Applet id → position, from the configuration
    readonly property var offsets: {
        try {
            return JSON.parse(Plasmoid.configuration.PopupOffsets || "{}");
        } catch (error) {
            return {};
        }
    }
    onOffsetsChanged: applyAll()

    // Applet id → anchor item
    property var anchorItems: ({})

    readonly property Component anchorComponent: Component {
        Item {
            // Popup start from the start of the panel window
            required property real offset
            required property var popup
            required property bool horizontal
            // The widget: the anchor takes its size across the panel
            required property Item widget

            // (scene coordinates: parent is the window content item)
            x: horizontal ? offset + popup.width / 2 : widgetRect.x
            y: horizontal ? widgetRect.y : offset + popup.height / 2
            width: horizontal ? 0 : widgetRect.width
            height: horizontal ? widgetRect.height : 0

            property rect widgetRect: Qt.rect(0, 0, 0, 0)
            function updateWidgetRect(): void {
                if (widget) {
                    const position = widget.mapToItem(null, 0, 0);
                    widgetRect = Qt.rect(position.x, position.y, widget.width, widget.height);
                }
            }
        }
    }

    Component.onCompleted: Qt.callLater(applyAll)

    Connections {
        target: placement.appletsModel
        function onCountChanged(): void {
            Qt.callLater(placement.applyAll);
        }
    }

    function plasmoidItems(): var {
        const items = [];
        for (let i = 0; i < appletsModel.count; i++) {
            const item = appletsModel.get(i).applet;
            if (item?.Plasmoid && item.fullRepresentation !== undefined) {
                items.push(item);
            }
        }
        return items;
    }

    // The popup window of a widget, or null (no popup, or not created yet)
    function popupOf(plasmoidItem: Item): var {
        const popup = plasmoidItem?.fullRepresentationItem?.Window.window;
        return popup?.objectName === "popupWindow" ? popup : null;
    }

    // Saved position of the popup of a widget, or undefined (centered)
    function offsetOf(plasmoidItem: Item): var {
        return offsets[plasmoidItem.Plasmoid.id];
    }

    // Current position of a popup start from the start of the panel window
    function currentOffset(popup: var): real {
        const panel = placement.Window.window;
        return horizontal ? popup.x - panel.x : popup.y - panel.y;
    }

    // Length of the panel window along the panel
    function panelLength(): real {
        const panel = placement.Window.window;
        return panel ? (horizontal ? panel.width : panel.height) : 0;
    }

    // Moves the popup of a widget (offset undefined: back to centered on its
    // widget). Saved in the configuration only when save is true (at the end
    // of a drag).
    function setOffset(plasmoidItem: Item, offset: var, save: bool): void {
        const id = plasmoidItem.Plasmoid.id;
        if (save) {
            const all = Object.assign({}, offsets);
            if (offset === undefined) {
                delete all[id];
            } else {
                all[id] = Math.round(offset);
            }
            Plasmoid.configuration.PopupOffsets = JSON.stringify(all); // (applyAll follows)
        } else {
            apply(plasmoidItem, offset);
        }
    }

    function applyAll(): void {
        const ids = [];
        for (const item of plasmoidItems()) {
            ids.push(String(item.Plasmoid.id));
            apply(item, offsetOf(item));
        }
        // Anchors of removed widgets
        for (const id in anchorItems) {
            if (!ids.includes(id)) {
                anchorItems[id].destroy();
                delete anchorItems[id];
            }
        }
    }

    function apply(plasmoidItem: Item, offset: var): void {
        const id = plasmoidItem.Plasmoid.id;
        let anchor = anchorItems[id];

        if (offset === undefined) {
            if (anchor) {
                const popup = anchor.popup;
                delete anchorItems[id];
                if (popup.visualParent === anchor) {
                    popup.visualParent = plasmoidItem.compactRepresentationItem;
                    popup.requestUpdate();
                }
                anchor.destroy();
            }
            return;
        }

        // The popup must exist to get its anchor before it opens: its content is
        // created without opening it
        if (!plasmoidItem.fullRepresentationItem && plasmoidItem.fullRepresentation) {
            const preload = plasmoidItem.preloadFullRepresentation;
            plasmoidItem.preloadFullRepresentation = true;
            plasmoidItem.preloadFullRepresentation = preload;
        }
        const popup = popupOf(plasmoidItem);
        const content = placement.Window.contentItem;
        if (!popup || !content) {
            return;
        }

        if (!anchor || anchor.popup !== popup) {
            anchor?.destroy();
            anchor = anchorComponent.createObject(content, {
                offset: offset,
                popup: popup,
                horizontal: Qt.binding(() => placement.horizontal),
                widget: plasmoidItem.compactRepresentationItem
            });
            anchorItems[id] = anchor;
            // At each opening: the widget may have moved in the panel since
            const createdAnchor = anchor;
            popup.visibleChanged.connect(() => {
                if (popup.visible && anchorItems[id] === createdAnchor) {
                    placeAgain(popup, createdAnchor);
                }
            });
        }
        anchor.offset = offset;
        placeAgain(popup, anchor);
    }

    // Placed again by Plasma on the anchor (it does when its visual parent
    // changes, at its next frame)
    function placeAgain(popup: var, anchor: Item): void {
        anchor.updateWidgetRect();
        popup.visualParent = null;
        popup.visualParent = anchor;
        popup.requestUpdate();
    }
}
