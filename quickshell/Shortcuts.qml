// Global shortcuts the Hyprland keybinds call into (`global quickshell:<name>`
// in hypr/modules/keys.lua). One entry per shortcut in the table below; the
// names are the contract with keys.lua, so renaming one means editing both.
//
// Instantiated once per bar (inside the Variants delegate) because several
// targets are bar-local items; everything it acts on is handed in as a
// property rather than looked up by id (the `Ref` suffix keeps a property
// from shadowing the id it is bound to).
import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: sc

    property var spotlightRef
    property var clipboardRef
    property var keybindsRef
    property var sysmonRef
    property var dayPanelRef
    property var wallpaperDeckRef
    property var regionSelectorRef
    property var workspaceOverviewRef
    property var apModRef
    property var quickModRef
    property var servicesModRef
    property var btModRef
    property Item clockAnchorRef

    readonly property var table: [
        { name: "spotlight", description: "Toggle app launcher",
          run: () => sc.spotlightRef.toggle() },
        // Pairs with Ctrl+D inside the launcher, which is what hides
        // an app. Getting back to one previously needed the launcher
        // open and an arrow press, which is a lot of steps for undoing
        // a single keystroke.
        { name: "unhide", description: "Open the hidden-apps list to show one again",
          run: () => sc.spotlightRef.manageHiddenApps() },
        { name: "clipboard", description: "Toggle clipboard history selector",
          run: () => sc.clipboardRef.toggle() },
        { name: "keybinds", description: "Toggle keybinds viewer",
          run: () => sc.keybindsRef.toggle() },
        { name: "powermenu", description: "Open the Power tab (session actions live there)",
          run: () => sc.apModRef.openTab("power") },
        { name: "sysmon", description: "Toggle system monitor",
          run: () => sc.sysmonRef.toggle() },
        { name: "quickactions", description: "Toggle quick actions panel",
          run: () => { sc.quickModRef._openAnchor = null; sc.quickModRef.popupOpen = !sc.quickModRef.popupOpen; } },
        { name: "audiopower", description: "Toggle audio & power panel (Sound tab)",
          run: () => sc.apModRef.openTab("sound") },
        { name: "calendar", description: "Toggle calendar popup",
          run: () => sc.dayPanelRef.toggleFrom(sc.clockAnchorRef) },
        { name: "wallpaper", description: "Deal the next wallpaper card (hold Super, release to apply)",
          run: () => sc.wallpaperDeckRef.step() },
        // Apply / cancel for the wallpaper deck. Global shortcuts
        // rather than keys on the deck's own surface: it is
        // click-through and never focused, and grabbing the keyboard to
        // read them broke the Super-release commit.
        { name: "wallpaper-apply", description: "Apply the wallpaper card in hand",
          run: () => sc.wallpaperDeckRef.commitIfOpen() },
        { name: "wallpaper-back", description: "Deal the previous wallpaper card",
          run: () => sc.wallpaperDeckRef.stepBack() },
        { name: "wallpaper-cancel", description: "Dismiss the wallpaper deck without applying",
          run: () => sc.wallpaperDeckRef.close() },
        { name: "screenshot-region", description: "Pick a region with the Quickshell region selector",
          run: () => sc.regionSelectorRef.start() },
        { name: "services", description: "Toggle background services panel",
          run: () => sc.servicesModRef.popupOpen = !sc.servicesModRef.popupOpen },
        { name: "bluetooth", description: "Toggle bluetooth menu",
          run: () => sc.btModRef.toggleOpen() },
        { name: "notifications", description: "Toggle notification center",
          run: () => sc.dayPanelRef.toggleFrom(null) },
        // Classic Super+Tab: open + cycle on Tab presses, release Super commits.
        { name: "overview-cycle", description: "Open overview / cycle next workspace",
          run: () => sc.workspaceOverviewRef.cycleOrOpen(1) },
        { name: "overview-cycle-prev", description: "Open overview / cycle previous workspace",
          run: () => sc.workspaceOverviewRef.cycleOrOpen(-1) }
    ]

    Instantiator {
        model: sc.table
        // modelData stays an implicit context property: a `required
        // property` delegate under an Instantiator can abort construction
        // silently (see the singleton warning in DESIGN.md).
        delegate: GlobalShortcut {
            appid: "quickshell"
            name: modelData.name
            description: modelData.description
            onPressed: modelData.run()
        }
    }
}
