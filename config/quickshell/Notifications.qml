// Notifications — the DBus notification server, the on-screen toast stack, and
// the history the day panel reads. Toasts expire on their own clock; history
// keeps them until dismissed. The center UI lives in NotifPane.qml.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import Quickshell.Services.UPower

Scope {
    id: root

    property var activeList: []
    property var historyList: []
    property int maxHistory: settingsStore.notifHistoryCap
    // Do not disturb: switched by hand (kept in the settings store, so the
    // settings app and a restart see it) or by the daily schedule. `quiet`
    // is what actually holds toasts back.
    readonly property bool dnd: settingsStore.dnd
    property bool scheduledQuiet: false
    // Turning DND off inside the scheduled window skips the rest of it.
    property double _scheduleSkippedUntil: 0
    readonly property bool quiet: dnd || scheduledQuiet
    function setDnd(on) {
        if (!on && scheduledQuiet) {
            _scheduleSkippedUntil = _windowEnd(new Date()).getTime();
            scheduledQuiet = false;
        }
        settingsStore.dnd = on;
    }
    function _minutes(hhmm) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm || "");
        return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
    }
    // Whether `now` falls in the from-to window; a window may run past
    // midnight (22:00-07:00).
    function _inWindow(now) {
        const from = _minutes(settingsStore.dndFrom), to = _minutes(settingsStore.dndTo);
        if (from < 0 || to < 0 || from === to) return false;
        const t = now.getHours() * 60 + now.getMinutes();
        return from < to ? (t >= from && t < to) : (t >= from || t < to);
    }
    function _windowEnd(now) {
        const end = new Date(now);
        const to = _minutes(settingsStore.dndTo);
        end.setHours(Math.floor(to / 60), to % 60, 0, 0);
        if (end <= now) end.setDate(end.getDate() + 1);
        return end;
    }
    function _checkSchedule() {
        const now = new Date();
        scheduledQuiet = settingsStore.dndSchedule && _inWindow(now) && now.getTime() >= _scheduleSkippedUntil;
    }
    Timer {
        interval: 30000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root._checkSchedule()
    }
    Connections {
        target: settingsStore
        function onDndScheduleChanged() { root._checkSchedule(); }
        function onDndFromChanged() { root._checkSchedule(); }
        function onDndToChanged() { root._checkSchedule(); }
    }

    // Per-app rules from the settings app: "quiet" files a notification
    // without a toast, "mute" drops it. Every sender is remembered so the
    // settings app can list it.
    function _appRule(appName) { return (settingsStore.notifAppRules || {})[appName] || ""; }
    function _remember(appName) {
        if (!appName) return;
        const seen = settingsStore.notifAppsSeen || [];
        if (seen.indexOf(appName) < 0) settingsStore.notifAppsSeen = [...seen, appName].sort();
    }
    function _playSound(n) {
        if (!settingsStore.notifSounds) return;
        // An app that asks for silence (the suppress-sound hint) gets it.
        if (n.hints && n.hints["suppress-sound"]) return;
        const volume = Math.max(0, Math.min(100, settingsStore.alertVolume)) / 100;
        Cmd.run(["pw-play", "--volume=" + volume, "/usr/share/sounds/freedesktop/stereo/message.oga"]);
    }
    property int unreadCount: 0
    // Bound to the day panel's open state (DayPanel owns the surface). Reading
    // the panel is what marks history seen and collapses the app groups.
    property bool panelOpen: false
    onPanelOpenChanged: {
        if (panelOpen) unreadCount = 0;
        else expandedGroups = ({});
    }

    function _entryFor(n) {
        return {
            id: n.id,
            time: new Date(),
            appName: n.appName || "",
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body: n.body || "",
            image: n.image || "",
            urgency: n.urgency,
            ref: n,
        };
    }
    // Toast + history. The toast expires on its own clock; the history entry
    // stays until dismissed, so a notification missed in passing is still
    // readable in the panel.
    function _push(n) {
        const entry = _entryFor(n);
        // Stamp the toast deadline here, not in the card: activeList is a plain
        // JS array, so every reassignment (a new toast, a close, an auto-expiry
        // sweep) rebuilds the Repeater's delegates. A card that re-derived its
        // own countdown would restart it each time, and a busy stack would
        // leave toasts up indefinitely. The entry object outlives the delegate,
        // so the deadline on it is stable.
        //
        // Everything expires, critical urgency included. An app may ask for
        // less than toastTimeout, never for more (and never for "forever").
        const ttl = n.expireTimeout > 0
            ? Math.min(n.expireTimeout, settingsStore.toastTimeout)
            : settingsStore.toastTimeout;
        entry.toastUntil = Date.now() + ttl;
        activeList = [entry, ...activeList].slice(0, settingsStore.toastMax);
        _file(entry);
    }
    // History only — no toast. Used for anything whose moment has passed or
    // that must not interrupt (see onNotification).
    function _pushHistory(n) { _file(_entryFor(n)); }
    function _file(entry) {
        if (_autoExpires(entry)) entry.expiresAt = Date.now() + settingsStore.notifAutoExpireDelay;
        historyList = [entry, ...historyList].slice(0, maxHistory);
        if (!panelOpen) unreadCount += 1;
    }

    // ===== Auto-expiry. Some senders are chatty enough that their history
    // entries are noise within a minute — Claude Code's agent pings arrive in
    // bursts and pile the center full. Matched entries carry a deadline and
    // leave on their own, toast and history together.
    //
    // A rule matches a substring of appName + summary because a terminal agent
    // has no app name of its own: kitty forwards Claude Code's OSC 99 to the
    // notification server as appName "kitty", summary "Claude Code".
    function _autoExpires(entry) {
        if (!settingsStore.notifAutoExpire) return false;
        const rules = (settingsStore.notifAutoExpireRules || [])
            .map(r => String(r).trim().toLowerCase())
            .filter(r => r !== "");
        if (rules.length === 0) return false;
        const hay = ((entry.appName || "") + " " + (entry.summary || "")).toLowerCase();
        return rules.some(r => hay.indexOf(r) >= 0);
    }
    readonly property bool _hasExpiring:
        historyList.some(e => e.expiresAt > 0) || activeList.some(e => e.expiresAt > 0)
    // One sweep for the whole list rather than a timer per entry, and it only
    // runs while something is actually pending.
    Timer {
        interval: 500
        repeat: true
        running: root._hasExpiring
        onTriggered: {
            const now = Date.now();
            const due = e => e.expiresAt > 0 && e.expiresAt <= now;
            // _dismissMatching reassigns both lists, so don't call it on a
            // tick where nothing is actually due.
            if (root.historyList.some(due) || root.activeList.some(due))
                root._dismissMatching(due);
        }
    }
    // Clearing history closes the underlying notifications too. They stay
    // tracked (and so replayable) until something dismisses them, so without
    // this a config reload would file everything straight back in.
    //
    // An entry whose notification the server already destroyed keeps a stale
    // wrapper: `ref` is still truthy but nothing on it is callable, and
    // touching it throws. That must not abort the sweep — it would leave the
    // list half-cleared, which is exactly what "Clear all" doing nothing
    // looked like.
    function _closeEntries(pred) {
        for (const e of historyList) {
            if (!pred(e)) continue;
            try { e.ref.dismiss(); } catch (err) { /* already gone */ }
        }
    }
    function dismissHistoryEntry(id) {
        _closeEntries(e => e.id === id);
        historyList = historyList.filter(e => e.id !== id);
    }
    // Copy a replaced notification's new text into its entries. The lists are
    // reassigned so the cards rebuild; a toast still on screen gets a fresh
    // deadline, as a new notification would.
    function _refresh(n) {
        const update = e => {
            if (e.id !== n.id) return e;
            const u = Object.assign({}, e, { summary: n.summary || "", body: n.body || "" });
            if (e.toastUntil !== undefined) {
                const ttl = n.expireTimeout > 0
                    ? Math.min(n.expireTimeout, settingsStore.toastTimeout)
                    : settingsStore.toastTimeout;
                u.toastUntil = Date.now() + ttl;
            }
            return u;
        };
        activeList = activeList.map(update);
        historyList = historyList.map(update);
    }
    function _remove(id) {
        activeList = activeList.filter(e => e.id !== id);
    }
    function clearHistory() {
        _closeEntries(e => true);
        historyList = [];
    }

    // Drop every notification matching `pred` from the toast stack *and* the
    // center history, closing the underlying server notification so it can't
    // come back on the next repaint.
    function _dismissMatching(pred) {
        for (const e of activeList) {
            if (!pred(e)) continue;
            try { e.ref.dismiss(); } catch (err) { /* already gone */ }
        }
        activeList = activeList.filter(e => !pred(e));
        historyList = historyList.filter(e => !pred(e));
        if (unreadCount > historyList.length) unreadCount = historyList.length;
    }
    // battery-notify.sh fires "Battery Low" / "Battery Critical", and the
    // bar's critical-suspend countdown uses the same wording. All of them are
    // stale the moment power comes back.
    function _isBatteryWarning(e) {
        return /^battery (low|critical)/i.test(e.summary || "");
    }
    // Idempotent — safe to call from every trigger below, and again on a
    // charge/discharge flap.
    function _onPowerRestored() { _dismissMatching(_isBatteryWarning); }

    // Two independent triggers, because they can fire apart from each other:
    // onBattery flips when the AC line goes online (the charger event proper),
    // while the display device reaches Charging/FullyCharged a moment later —
    // and on a full battery, or a dock that reports line power without a
    // charge cycle, only one of the two moves at all.
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (!UPower.onBattery) root._onPowerRestored();
        }
    }
    Connections {
        target: UPower.displayDevice
        ignoreUnknownSignals: true
        function onStateChanged() {
            const st = UPower.displayDevice ? UPower.displayDevice.state : 0;
            if (st === UPowerDeviceState.Charging || st === UPowerDeviceState.FullyCharged)
                root._onPowerRestored();
        }
    }

    // ===== Grouping (center view): history bucketed by appName, newest
    // group first, and within each app bucketed again by summary — a
    // screenshot tool firing ten times is one stack, not ten rows.
    // expandedGroups tracks both levels of "N more…" state (keyed by app
    // for the group, by groupKey() for the stack) and resets when the
    // center closes.
    property var expandedGroups: ({})
    // Stack identity: same app, same summary. NUL-joined so an app name
    // containing the separator can't collide with a summary.
    function groupKey(app, summary) { return app + "\u0000" + summary; }
    readonly property var groupedHistory: {
        const groups = [];
        const idx = {};
        for (const e of historyList) {
            const k = e.appName || "unknown";
            if (idx[k] === undefined) {
                idx[k] = groups.length;
                groups.push({ app: k, entries: [], clusters: [], clusterIdx: {} });
            }
            const g = groups[idx[k]];
            g.entries.push(e);
            const ck = e.summary || "";
            if (g.clusterIdx[ck] === undefined) {
                g.clusterIdx[ck] = g.clusters.length;
                g.clusters.push({ key: root.groupKey(k, ck), summary: ck, entries: [] });
            }
            g.clusters[g.clusterIdx[ck]].entries.push(e);
        }
        return groups;
    }
    function clearApp(app) {
        _closeEntries(e => (e.appName || "unknown") === app);
        historyList = historyList.filter(e => (e.appName || "unknown") !== app);
    }
    // Dismiss a whole stack: every entry the collapsed row stands for.
    function clearCluster(app, summary) {
        const hit = e => (e.appName || "unknown") === app && (e.summary || "") === summary;
        _closeEntries(hit);
        historyList = historyList.filter(e => !hit(e));
    }
    function toggleGroup(app) {
        const m = Object.assign({}, expandedGroups);
        m[app] = !(m[app] === true);
        expandedGroups = m;   // reassign — never mutate in place
    }
    // Resolve a usable icon source for a notification entry: prefer embedded
    // image data, then the app icon (a file path as-is, or a theme name via
    // iconPath), finally a generic fallback so every notification shows one.
    // A filesystem path has to be handed over as an explicit file:// URL.
    // Passed bare, QML resolves it against the component's base URL — which
    // for a Quickshell type is qrc: — and the icon silently fails to load as
    // "qrc:/usr/lib64/kitty/logo/kitty.png". Anything already carrying a
    // scheme is left alone.
    function _iconUrl(s) {
        if (s.indexOf("://") >= 0) return s;
        if (s.charAt(0) === "~") return "file://" + Quickshell.env("HOME") + s.slice(1);
        if (s.charAt(0) === "/") return "file://" + s;
        return "";   // not a path — caller resolves it as a theme name
    }
    function iconFor(entry) {
        if (!entry) return "";
        if (entry.image) {
            const img = _iconUrl(entry.image);
            if (img !== "") return img;
        }
        const ic = entry.appIcon || "";
        if (ic !== "") {
            const asPath = _iconUrl(ic);
            if (asPath !== "") return asPath;
            return Quickshell.iconPath(ic, "dialog-information");
        }
        return Quickshell.iconPath("dialog-information", "");
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true
        persistenceSupported: true

        onNotification: (n) => {
            n.tracked = true;
            n.closed.connect(() => root._remove(n.id));
            // A sender that replaces its notification (progress, now playing)
            // updates this same object in place; onNotification does not fire
            // again, so follow the text here.
            n.summaryChanged.connect(() => root._refresh(n));
            n.bodyChanged.connect(() => root._refresh(n));
            // Carried over from the previous config generation: it already had
            // its showing, so file it in history rather than toasting it a
            // second time. Anything arriving under DND, or from an app set to
            // "quiet", takes the same path — those suppress the interruption,
            // not the notification. A muted app's notification is dropped.
            root._remember(n.appName);
            const rule = root._appRule(n.appName);
            if (rule === "mute") { n.dismiss(); return; }
            if (n.lastGeneration || root.quiet || rule === "quiet") { root._pushHistory(n); return; }
            root._push(n);
            root._playSound(n);
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: stackWindow
            required property var modelData
            screen: modelData
            // Anchor only top so the surface width matches stackCol exactly
            // (380 px) instead of spanning the screen. Clicks left/right of
            // the toast pass through to underlying windows.
            anchors { top: true; right: settingsStore.toastPosition === "right" }
            margins { top: 40; right: settingsStore.toastPosition === "right" ? 12 : 0 }
            implicitWidth: settingsStore.toastWidth
            implicitHeight: Math.max(1, stackCol.implicitHeight)
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // When there are no active toasts, drop the input region entirely
            // so the 1 px placeholder strip doesn't intercept clicks.
            mask: root.activeList.length === 0 ? emptyRegion : null
            Region { id: emptyRegion }

            ColumnLayout {
                id: stackCol
                width: settingsStore.toastWidth
                anchors.top: parent.top
                spacing: 0
                Repeater {
                    model: root.activeList
                    delegate: NotificationCard {
                        required property var modelData
                        entry: modelData
                        Layout.fillWidth: true
                        onDismiss: { if (modelData.ref) modelData.ref.dismiss(); }
                        // Timing out only hides the toast. The notification
                        // stays open on the server, so its history entry
                        // survives a config reload and the app is not told
                        // the user dismissed it.
                        onTimedOut: root._remove(modelData.id)
                    }
                }
            }
        }
    }

    component NotificationCard: Item {
        id: card
        property var entry
        signal dismiss()
        signal timedOut()
        implicitHeight: cardBg.implicitHeight + 16

        Rectangle {
            id: cardBg
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 14
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            implicitHeight: cardCol.implicitHeight + 24
            radius: Theme.radius.lg
            color: card.entry && card.entry.urgency === NotificationUrgency.Critical
                ? Theme.accent.red : Theme.popupBorder
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.scrim
                shadowOpacity: 0.95
                shadowBlur: 1.5
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 10
                autoPaddingEnabled: true
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(0, Theme.radius.lg - 2)
                color: Theme.bg
            }
        }

        ColumnLayout {
            id: cardCol
            anchors.fill: cardBg
            anchors.margins: Theme.spacing.lg
            spacing: Theme.spacing.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                IconImage {
                    visible: source != ""
                    source: root.iconFor(card.entry)
                    implicitSize: 24
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: card.entry ? (card.entry.summary || card.entry.appName) : ""
                        textFormat: Text.PlainText   // external text: never render markup
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.entry && card.entry.appName && card.entry.summary
                        text: card.entry ? card.entry.appName : ""
                        textFormat: Text.PlainText   // external text: never render markup
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    implicitWidth: 26; implicitHeight: 26; radius: 13 * Theme.radiusScale
                    color: closeMouse.containsMouse ? Theme.borderStrong : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"; color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xxl
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.dismiss()
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: card.entry && card.entry.body !== ""
                text: card.entry ? card.entry.body : ""
                color: Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            RowLayout {
                id: actRow
                // Inline-component root ids ("card") don't resolve from
                // delegate contexts at runtime — bounce through this row.
                readonly property var dismissCard: () => card.dismiss()
                Layout.fillWidth: true
                spacing: Theme.spacing.sm
                visible: card.entry && card.entry.ref && card.entry.ref.actions && card.entry.ref.actions.length > 0
                Repeater {
                    model: card.entry && card.entry.ref ? card.entry.ref.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        implicitHeight: 26
                        implicitWidth: actText.implicitWidth + 16
                        radius: 4 * Theme.radiusScale
                        color: actMouse.containsMouse ? Theme.bgActive : Theme.bgAlt
                        border.color: Theme.borderStrong; border.width: 1
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: modelData.text
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                        }
                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { modelData.invoke(); actRow.dismissCard(); }
                        }
                    }
                }
            }
        }

        // Counts down to the deadline stamped in _push. Date.now() is not
        // reactive, so this is evaluated once per delegate — on a rebuild the
        // card picks up the time already served instead of starting over.
        Timer {
            interval: Math.max(1, (card.entry ? card.entry.toastUntil : 0) - Date.now())
            running: true
            repeat: false
            onTriggered: card.timedOut()
        }
    }
}
