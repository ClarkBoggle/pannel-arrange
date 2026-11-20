/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.plasmoid

// Keeps popups where the user moved them along the panel, and keeps their size.
// Always active, not only in edit mode.
//
// Plasma always centers a popup on its "visual parent" (normally the widget)
// and does it again whenever the popup is resized or shown, so a popup cannot
// simply be moved. Instead, a moved popup gets an invisible anchor item in the
// panel, centered where the popup should be, and the anchor becomes its visual
// parent: Plasma then puts the popup there by itself.
//
// Positions are saved in the PopupOffsets setting, by applet id: the distance
// in pixels from the start of the panel to the start (left or top edge) of the
// popup. Moving is done by PopupHandles, in edit mode, through setOffset().
Item {
    id: placement

    // The items of the panel ({ applet })
    required property ListModel appletsModel
    required property bool horizontal

    // Applet id → saved position
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

    // Widgets, popup contents and popups already watched (see watch())
    property var watchedItems: []

    Component.onCompleted: Qt.callLater(applyAll)

    Connections {
        target: placement.appletsModel
        function onCountChanged(): void {
            Qt.callLater(placement.applyAll);
        }
    }

    readonly property Component anchorComponent: Component {
        Item {
            id: anchor

            required property int appletId
            required property var popup
            required property Item widget
            required property bool horizontal
            // Where the popup starts, from the start of the panel
            required property real offset
            // While the popup is being resized: the length it is about to get.
            // Plasma places the popup again as soon as its size changes, so the
            // anchor must already be in its new place by then; otherwise the
            // popup shows for one frame centered on the old place and shakes.
            property var askedLength: undefined

            // The widget's rectangle, in the panel window
            property rect widgetRect: Qt.rect(0, 0, 0, 0)

            // Centered on the popup along the panel; across, as large as the
            // widget, so that the popup stays against the panel.
            // (the anchor is a child of the window's content item)
            x: horizontal ? offset + (askedLength ?? popup.width) / 2 : widgetRect.x
            y: horizontal ? widgetRect.y : offset + (askedLength ?? popup.height) / 2
            width: horizontal ? 0 : widgetRect.width
            height: horizontal ? widgetRect.height : 0

            // Plasma may have placed the popup before the anchor followed its
            // new size: place it again after each move of the anchor
            onXChanged: Qt.callLater(placeAgainIfCurrent)
            onYChanged: Qt.callLater(placeAgainIfCurrent)

            function placeAgainIfCurrent(): void {
                if (placement.anchorItems[appletId] === anchor && popup.visualParent === anchor) {
                    placement.placeAgain(popup, anchor);
                }
            }

            function updateWidgetRect(): void {
                if (widget) {
                    const position = widget.mapToItem(null, 0, 0);
                    widgetRect = Qt.rect(position.x, position.y, widget.width, widget.height);
                }
            }
        }
    }

    // The widgets of the panel that have a popup
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

    // The popup window of a widget, or null if it does not exist yet
    function popupOf(plasmoidItem: Item): var {
        const popup = plasmoidItem?.fullRepresentationItem?.Window.window;
        return popup?.objectName === "popupWindow" ? popup : null;
    }

    // The saved position of a widget's popup, or undefined if centered
    function offsetOf(plasmoidItem: Item): var {
        return offsets[plasmoidItem.Plasmoid.id];
    }

    // Where a popup currently starts, from the start of the panel
    function currentOffset(popup: var): real {
        const panel = placement.Window.window;
        return horizontal ? popup.x - panel.x : popup.y - panel.y;
    }

    function panelLength(): real {
        const panel = placement.Window.window;
        if (!panel) {
            return 0;
        }
        return horizontal ? panel.width : panel.height;
    }

    // Moves the popup of a widget; offset undefined puts it back centered.
    // Saved only if `save` is true (at the end of a drag). `length`: the size
    // the popup is about to get, while it is resized (see askedLength).
    function setOffset(plasmoidItem: Item, offset: var, save: bool, length: var): void {
        if (!save) {
            apply(plasmoidItem, offset, undefined, length);
            return;
        }
        const all = Object.assign({}, offsets);
        const id = plasmoidItem.Plasmoid.id;
        if (offset === undefined) {
            delete all[id];
        } else {
            all[id] = Math.round(offset);
        }
        // Calls applyAll() through onOffsetsChanged, if anything changed
        Plasmoid.configuration.PopupOffsets = JSON.stringify(all);
        if (offset !== undefined) {
            apply(plasmoidItem, offset);
        }
    }

    function applyAll(): void {
        const ids = [];
        for (const item of plasmoidItems()) {
            ids.push(String(item.Plasmoid.id));
            watch(item);
            apply(item, offsetOf(item));
        }
        // Anchors of widgets removed from the panel
        for (const id in anchorItems) {
            if (!ids.includes(id)) {
                anchorItems[id].destroy();
                delete anchorItems[id];
            }
        }
    }

    // `knownPopup`: the popup window, when the caller already knows it
    function apply(plasmoidItem: Item, offset: var, knownPopup: var, length: var): void {
        const id = plasmoidItem.Plasmoid.id;
        let anchor = anchorItems[id];

        if (offset === undefined) {
            if (anchor) {
                removeAnchor(plasmoidItem, anchor);
            }
            return;
        }

        // Most popups are only created when first opened: watch() applies
        // the position then
        watch(plasmoidItem);
        const popup = knownPopup ?? popupOf(plasmoidItem);
        const content = placement.Window.contentItem;
        if (!popup || !content) {
            return;
        }

        if (anchor?.popup !== popup) {
            anchor?.destroy();
            anchor = createAnchor(plasmoidItem, popup, offset, content);
        }
        anchor.askedLength = length;
        anchor.offset = offset;
        placeAgain(popup, anchor);
    }

    function createAnchor(plasmoidItem: Item, popup: var, offset: real, content: Item): Item {
        const id = plasmoidItem.Plasmoid.id;
        const anchor = anchorComponent.createObject(content, {
            appletId: id,
            offset: offset,
            popup: popup,
            horizontal: Qt.binding(() => placement.horizontal),
            widget: plasmoidItem.compactRepresentationItem
        });
        anchorItems[id] = anchor;

        // Placed again at each opening: the widget may have moved in the panel
        popup.visibleChanged.connect(() => {
            if (popup.visible && anchorItems[id] === anchor) {
                placeAgain(popup, anchor);
            }
        });
        return anchor;
    }

    // Back to centered on the widget
    function removeAnchor(plasmoidItem: Item, anchor: Item): void {
        const popup = anchor.popup;
        delete anchorItems[plasmoidItem.Plasmoid.id];
        if (popup.visualParent === anchor) {
            popup.visualParent = plasmoidItem.compactRepresentationItem;
            popup.requestUpdate();
        }
        anchor.destroy();
    }

    // Plasma places a popup again when its visual parent changes, at its next
    // frame
    function placeAgain(popup: var, anchor: Item): void {
        anchor.updateWidgetRect();
        popup.visualParent = null;
        popup.visualParent = anchor;
        popup.requestUpdate();
    }

    // Plasma creates a widget's popup content when the popup is first opened,
    // puts it in the popup, and only then shows the popup. So the position is
    // applied as soon as the content gets its window, before the popup is
    // shown. Every widget is watched, for keepSize() too.
    function watch(plasmoidItem: Item): void {
        if (!startWatching(plasmoidItem)) {
            return;
        }
        const watchContent = () => {
            const content = plasmoidItem.fullRepresentationItem;
            if (content && startWatching(content)) {
                // Use the window given by the signal: the item's attached
                // Window property is not updated yet at that time
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

    // Returns false if the item was already watched
    function startWatching(item: var): bool {
        // (destroyed items become null)
        watchedItems = watchedItems.filter(watched => watched);
        if (watchedItems.includes(item)) {
            return false;
        }
        watchedItems.push(item);
        return true;
    }

    // Plasma grows a popup to the minimum size of its content, but never
    // shrinks it back when that minimum goes down again. Some widgets ask for
    // a larger minimum for a moment while loading (the CPU monitor asks for
    // 300 px high, then 212): their popup would keep that size, and Plasma
    // would save it. Here the size from before is given back once the minimum
    // allows it again.
    function keepSize(popup: var): void {
        if (!startWatching(popup)) {
            return;
        }
        // (the minimum changes before Plasma grows the popup)
        let heldWidth = 0;
        let heldHeight = 0;
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
}
