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
// The anchor is set when the popup gets the full representation (often at its
// first opening). Moving a popup is done by PopupHandles (edit mode), through
// setOffset().
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
            id: anchorItem
            // Id of the applet of the popup
            required property int appletId
            // Popup start from the start of the panel window
            required property real offset
            // Popup length along the panel asked while it is resized by the
            // user, else undefined (the length of the popup). Set before the
            // popup is resized: Plasma places the popup again when its size
            // changes, the anchor must already be where the popup will be
            // (else the popup is shown one frame centered on the old place,
            // and shakes while resized)
            property var askedLength: undefined
            required property var popup
            required property bool horizontal
            // The widget: the anchor takes its size across the panel
            required property Item widget

            // (scene coordinates: parent is the window content item)
            x: horizontal ? offset + (askedLength ?? popup.width) / 2 : widgetRect.x
            y: horizontal ? widgetRect.y : offset + (askedLength ?? popup.height) / 2
            width: horizontal ? 0 : widgetRect.width
            height: horizontal ? widgetRect.height : 0

            // The anchor follows the popup size, but Plasma may have placed the
            // popup before (e.g. its size changing after its first placement,
            // once its frame is known): placed again after each anchor move
            onXChanged: Qt.callLater(placeAgain)
            onYChanged: Qt.callLater(placeAgain)
            function placeAgain(): void {
                if (placement.anchorItems[appletId] === anchorItem && popup.visualParent === anchorItem) {
                    placement.placeAgain(popup, anchorItem);
                }
            }

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
    // of a drag). length: the length along the panel the popup is about to be
    // given, while it is resized (see askedLength).
    function setOffset(plasmoidItem: Item, offset: var, save: bool, length: var): void {
        const id = plasmoidItem.Plasmoid.id;
        if (save) {
            const all = Object.assign({}, offsets);
            if (offset === undefined) {
                delete all[id];
            } else {
                all[id] = Math.round(offset);
            }
            Plasmoid.configuration.PopupOffsets = JSON.stringify(all); // (applyAll follows when changed)
            if (offset !== undefined) {
                apply(plasmoidItem, offset);
            }
        } else {
            apply(plasmoidItem, offset, undefined, length);
        }
    }

    function applyAll(): void {
        const ids = [];
        for (const item of plasmoidItems()) {
            ids.push(String(item.Plasmoid.id));
            watch(item);
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

    // (knownPopup: the popup window when already known, see watch())
    function apply(plasmoidItem: Item, offset: var, knownPopup: var, length: var): void {
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

        // The popup is often created only at the first opening: applied then
        watch(plasmoidItem);
        const popup = knownPopup ?? popupOf(plasmoidItem);
        const content = placement.Window.contentItem;
        if (!popup || !content) {
            return;
        }

        if (!anchor || anchor.popup !== popup) {
            anchor?.destroy();
            anchor = anchorComponent.createObject(content, {
                appletId: id,
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
        anchor.askedLength = length;
        anchor.offset = offset;
        placeAgain(popup, anchor);
    }

    // Widgets and full representations already watched
    property var watchedItems: []

    // At its first opening, Plasma creates the full representation of a widget
    // and puts it in the popup, and only then shows the popup: the position is
    // applied when the full representation gets its window, before the popup
    // is placed. Its size is kept from then on (keepSize()). All the widgets
    // are watched.
    function watch(plasmoidItem: Item): void {
        watchedItems = watchedItems.filter(item => item); // (destroyed: null)
        if (watchedItems.includes(plasmoidItem)) {
            return;
        }
        watchedItems.push(plasmoidItem);
        const watchContent = () => {
            const content = plasmoidItem.fullRepresentationItem;
            if (content && !watchedItems.includes(content)) {
                watchedItems.push(content);
                // (the window given by the signal: the attached Window
                // property of the item is not updated yet at that time)
                content.windowChanged.connect(window => {
                    if (window?.objectName !== "popupWindow") {
                        return;
                    }
                    placement.keepSize(window);
                    const offset = placement.offsetOf(plasmoidItem);
                    if (offset !== undefined) {
                        placement.apply(plasmoidItem, offset, window);
                    }
                });
            }
            const popup = placement.popupOf(plasmoidItem);
            if (popup) {
                placement.keepSize(popup);
            }
        };
        plasmoidItem.fullRepresentationItemChanged.connect(watchContent);
        watchContent();
    }

    // Plasma enlarges a popup to the minimum size of its content, and does not
    // shrink it back when that minimum goes down again. Some widgets ask a
    // larger minimum for a moment while they load (CPU monitor: 300 px high,
    // then 212): the popup kept the larger size, saved when it closed, so the
    // size set by the user was lost. The size before such a temporary minimum is
    // given back once the minimum goes down to it again.
    function keepSize(popup: var): void {
        if (watchedItems.includes(popup)) {
            return;
        }
        watchedItems.push(popup);
        let heldWidth = 0;
        let heldHeight = 0;
        // (the minimum changes before Plasma enlarges the popup)
        popup.minimumWidthChanged.connect(() => {
            if (popup.minimumWidth > popup.width) {
                heldWidth = heldWidth || popup.width;
            } else if (heldWidth && popup.minimumWidth <= heldWidth) {
                const width = heldWidth;
                heldWidth = 0;
                if (popup.width > width) {
                    popup.width = width;
                }
            }
        });
        popup.minimumHeightChanged.connect(() => {
            if (popup.minimumHeight > popup.height) {
                heldHeight = heldHeight || popup.height;
            } else if (heldHeight && popup.minimumHeight <= heldHeight) {
                const height = heldHeight;
                heldHeight = 0;
                if (popup.height > height) {
                    popup.height = height;
                }
            }
        });
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
