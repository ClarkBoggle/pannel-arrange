/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Popup resizing, in edit mode:
//
// - A click on a widget shown as an icon in the panel opens its popup, instead
//   of the panel configuration (main.qml), or, while it is open, instead of the
//   menu of ConfigOverlay (which still shows when the mouse is over the widget,
//   but not while the popup is open). A second click closes it.
// - The popup gets resize handles (PopupHandles.qml); its size snaps to the
//   plasmoid grid of plasma-arrange: the grid of the desktop shown on the
//   screen of the popup. Without plasma-arrange, the size is free.
//
// The plasmoid grid comes from GridDrag.js of plasma-arrange, a library script
// shared by the whole shell (one QML engine), in which every desktop registers
// itself. It is loaded from its installed package, next to this one, at run
// time: when plasma-arrange is not installed, nothing breaks.
QtObject {
    id: popupResize

    // A popup opened by a click is open (ConfigOverlay then hides its menu)
    readonly property bool popupOpen: handles !== null

    // The widget (PlasmoidItem) whose popup was opened, and the handles put in it
    property Item applet: null
    property Item handles: null

    // Last popup closed, and when: a click on its widget closes it (the popup
    // loses the focus) just before the click itself is seen, which must not
    // open it again
    property Item closedApplet: null
    property double closedTime: 0

    // GridDrag.js of plasma-arrange: undefined before loading it, null when
    // not installed
    property var gridDrag: undefined

    readonly property Component handlesComponent: Component {
        PopupHandles {
            cellOn: screenName => popupResize.plasmoidCellOn(screenName)
        }
    }

    // Edit mode
    property bool active: false

    onActiveChanged: {
        // Edit mode ended: the popup stays open, without handles
        if (!active) {
            handles?.destroy();
            handles = null;
            applet = null;
        }
    }

    // Opens or closes the popup of the widget of an applet container of the
    // panel. Returns false when the widget has no popup (shown in full in the
    // panel): ConfigOverlay then shows its menu.
    function toggle(container: Item): bool {
        const plasmoidItem = container?.applet;
        if (!active || !plasmoidItem?.fullRepresentation || !plasmoidItem.compactRepresentationItem?.visible) {
            return false;
        }

        if (plasmoidItem.expanded) {
            plasmoidItem.expanded = false;
            return true;
        }
        if (plasmoidItem === closedApplet && Date.now() - closedTime < 300) {
            return true; // (already closed by this click)
        }

        if (applet && applet !== plasmoidItem) {
            applet.expanded = false;
        }
        applet = plasmoidItem;
        plasmoidItem.expanded = true;
        // (the full representation may only be created now)
        Qt.callLater(addHandles);
        return true;
    }

    function addHandles(): void {
        handles?.destroy();
        handles = null;
        const content = applet?.fullRepresentationItem;
        // In the popup, the full representation fills its main item
        const popup = content?.Window.window;
        if (!applet?.expanded || !popup || popup.objectName !== "popupWindow") {
            return;
        }
        const item = handlesComponent.createObject(content.parent);
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

    // Plasmoid grid cell of the desktop shown on a screen: { width, height },
    // or null (plasma-arrange not installed, or a Folder View desktop)
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
            return null; // plasma-arrange is not installed
        }
    }
}
