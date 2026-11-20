/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

// Opens widget popups from the panel edit mode, with resize handles.
//
// Created by ConfigOverlay, so it only exists in edit mode. A click on a widget
// opens its popup (ConfigOverlay hides its own menu meanwhile), a second click
// closes it. Widgets without a popup keep the usual menu.
//
// The popup snaps to the plasmoid grid of plasma-arrange, if installed: the
// grid of the desktop shown on the popup's screen. That grid is read from
// plasma-arrange's GridDrag.js, a script shared by the whole shell in which
// every desktop registers itself.
QtObject {
    id: popupResize

    required property PopupPlacement placement

    // True while a popup opened by a click is shown
    readonly property bool popupOpen: handles !== null

    // The widget whose popup is open, and the handles shown in that popup
    property Item applet: null
    property Item handles: null

    // Clicking the widget of an open popup first closes the popup (it loses
    // focus), and only then do we see the click: it must not reopen it.
    property Item closedApplet: null
    property double closedTime: 0

    // GridDrag.js of plasma-arrange: undefined until loaded, null if missing
    property var gridDrag: undefined

    readonly property Component handlesComponent: Component {
        PopupHandles {
            cellOn: screenName => popupResize.plasmoidCellOn(screenName)
            placement: popupResize.placement
        }
    }

    // Leaving edit mode: the handles go away, the popup stays open
    Component.onDestruction: handles?.destroy()

    // Opens or closes the popup of a widget of the panel (an applet container).
    // Returns false if the widget has no popup: ConfigOverlay then shows its
    // menu instead.
    function toggle(container: Item): bool {
        const plasmoidItem = container?.applet;
        if (!plasmoidItem?.fullRepresentation || !plasmoidItem.compactRepresentationItem?.visible) {
            return false;
        }

        // Some widgets have an empty popup, only because Plasma requires one
        // (e.g. Catwalk). Create the content without opening it, to check.
        if (!plasmoidItem.fullRepresentationItem) {
            const preload = plasmoidItem.preloadFullRepresentation;
            plasmoidItem.preloadFullRepresentation = true;
            plasmoidItem.preloadFullRepresentation = preload;
        }
        if (isEmpty(plasmoidItem.fullRepresentationItem)) {
            return false;
        }

        if (plasmoidItem.expanded) {
            plasmoidItem.expanded = false;
            return true;
        }
        const justClosed = plasmoidItem === closedApplet && Date.now() - closedTime < 300;
        if (justClosed) {
            return true;
        }

        if (applet && applet !== plasmoidItem) {
            applet.expanded = false;
        }
        applet = plasmoidItem;
        plasmoidItem.expanded = true;
        // The popup content may only be created now
        Qt.callLater(addHandles);
        return true;
    }

    function isEmpty(item: Item): bool {
        return !item || (item.children.length === 0
                         && item.implicitWidth <= 0 && item.implicitHeight <= 0
                         && !(item.Layout.preferredWidth > 0) && !(item.Layout.preferredHeight > 0));
    }

    function addHandles(): void {
        handles?.destroy();
        handles = null;

        const content = applet?.fullRepresentationItem;
        const popup = content?.Window.window;
        if (!applet?.expanded || popup?.objectName !== "popupWindow") {
            return;
        }
        // Next to the content, in the popup's main item, which they fill
        const item = handlesComponent.createObject(content.parent, { plasmoidItem: applet });
        item.closed.connect(() => popupClosed(item));
        handles = item;
    }

    function popupClosed(item: Item): void {
        if (item !== handles) {
            return;
        }
        closedApplet = applet;
        closedTime = Date.now();
        handles = null;
        applet = null;
        item.destroy();
    }

    // The plasmoid grid cell ({ width, height }) of the desktop shown on a
    // screen, or null: no plasma-arrange, or a desktop without its grid.
    function plasmoidCellOn(screenName: string): var {
        if (gridDrag === undefined) {
            gridDrag = loadGridDrag();
        }
        for (const desktop of gridDrag?.desktops() ?? []) {
            const cell = desktop?.plasmoidCellOn?.(screenName);
            if (cell) {
                return cell;
            }
        }
        return null;
    }

    // Imported with the same URL as the desktop does, to get the same shared
    // instance. Loaded at run time so that a missing plasma-arrange breaks
    // nothing.
    function loadGridDrag(): var {
        const url = Qt.resolvedUrl("../../../org.kde.desktopcontainment/contents/ui/GridDrag.js");
        try {
            return Qt.createQmlObject(`
                import QtQml
                import "${url}" as GridDrag
                QtObject {
                    function desktops(): var {
                        return GridDrag.desktops ?? [];
                    }
                }`, popupResize, "PlasmaArrangeGrid");
        } catch (error) {
            return null;
        }
    }
}
