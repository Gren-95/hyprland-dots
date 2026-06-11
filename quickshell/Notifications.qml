import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

Scope {
    id: root

    property var activeList: []
    property var historyList: []
    property int maxHistory: 50
    property bool dnd: false
    property bool pinned: false
    property int unreadCount: 0
    property bool centerOpen: false

    function _push(n) {
        const entry = {
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
        activeList = [entry, ...activeList].slice(0, 5);
        historyList = [entry, ...historyList].slice(0, maxHistory);
        if (!centerOpen) unreadCount += 1;
    }
    function openCenter() { centerOpen = true; unreadCount = 0; }
    function closeCenter() { centerOpen = false; }
    function toggleCenter() { centerOpen = !centerOpen; if (centerOpen) unreadCount = 0; }
    function dismissHistoryEntry(id) {
        historyList = historyList.filter(e => e.id !== id);
    }
    function _remove(id) {
        activeList = activeList.filter(e => e.id !== id);
    }
    function clearHistory() { historyList = []; }
    // Resolve a usable icon source for a notification entry: prefer embedded
    // image data, then the app icon (a file path as-is, or a theme name via
    // iconPath), finally a generic fallback so every notification shows one.
    function iconFor(entry) {
        if (!entry) return "";
        if (entry.image) return entry.image;
        const ic = entry.appIcon || "";
        if (ic !== "") {
            if (ic.charAt(0) === "/" || ic.indexOf("://") >= 0 || ic.charAt(0) === "~")
                return ic;
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
            if (!root.dnd) root._push(n);
            else root.historyList = [{
                id: n.id, time: new Date(), appName: n.appName || "", appIcon: n.appIcon || "",
                summary: n.summary || "", body: n.body || "", image: n.image || "",
                urgency: n.urgency, ref: n,
            }, ...root.historyList].slice(0, root.maxHistory);
            n.closed.connect(() => root._remove(n.id));
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
            anchors { top: true }
            margins { top: 40 }
            implicitWidth: 380
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
                width: 380
                anchors.top: parent.top
                spacing: 0
                Repeater {
                    model: root.activeList
                    delegate: NotificationCard {
                        required property var modelData
                        entry: modelData
                        Layout.fillWidth: true
                        onDismiss: { if (modelData.ref) modelData.ref.dismiss(); }
                    }
                }
            }
        }
    }

    // ============ Notification center: full-screen overlay listing history ============
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: centerWindow
            required property var modelData
            screen: modelData
            visible: root.centerOpen
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.45
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeCenter()
                }
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: 560
                height: 620
                radius: Theme.radius.lg
                color: Theme.bgAlt
                border.color: Theme.borderStrong
                border.width: 1
                focus: root.centerOpen
                scale: root.centerOpen ? 1.0 : 0.96
                opacity: root.centerOpen ? 1.0 : 0.0
                transformOrigin: Item.Center
                Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.closeCenter(); e.accepted = true; }
                }

                ColumnLayout {
                    id: centerHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: Theme.spacing.lg
                    spacing: Theme.spacing.md
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.md
                        Text {
                            text: "󰂚"
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xxl
                        }
                        Text {
                            text: "Notifications"
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                            font.bold: true
                        }
                        Text {
                            text: root.historyList.length + " items"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            visible: root.historyList.length > 0
                            implicitWidth: clearText.implicitWidth + 16
                            implicitHeight: 26
                            radius: 4
                            color: clearMouse.containsMouse ? "#7f1d1d" : "transparent"
                            border.color: "#7f1d1d"
                            border.width: 1
                            Text {
                                id: clearText
                                anchors.centerIn: parent
                                text: "Clear all"
                                color: clearMouse.containsMouse ? Theme.fg : "#f87171"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                            }
                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearHistory()
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }
                }

                Flickable {
                    id: historyView
                    anchors {
                        top: centerHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        topMargin: 6
                        leftMargin: 8
                        rightMargin: 8
                        bottomMargin: 8
                    }
                    contentHeight: historyCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: historyCol
                        width: parent.width
                        spacing: Theme.spacing.xs
                        Repeater {
                            model: root.historyList
                            delegate: HistoryRow {
                                required property var modelData
                                entry: modelData
                                Layout.fillWidth: true
                                onDismissed: root.dismissHistoryEntry(modelData.id)
                            }
                        }
                        Text {
                            visible: root.historyList.length === 0
                            text: "No notifications"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.md
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 32
                        }
                    }
                }
            }
        }
    }

    component HistoryRow: Rectangle {
        id: hist
        property var entry
        signal dismissed()
        implicitHeight: histCol.implicitHeight + 16
        radius: 8
        color: histHover.containsMouse ? Theme.bgHover : Theme.bg
        border.color: Theme.border
        border.width: 1

        ColumnLayout {
            id: histCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: Theme.spacing.xs
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                IconImage {
                    visible: source != ""
                    source: root.iconFor(hist.entry)
                    implicitSize: 18
                }
                Text {
                    Layout.fillWidth: true
                    text: hist.entry ? (hist.entry.summary || hist.entry.appName) : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: hist.entry ? Qt.formatTime(hist.entry.time, "hh:mm") : ""
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
                Rectangle {
                    implicitWidth: 20; implicitHeight: 20; radius: 10
                    color: dismissMouse.containsMouse ? Theme.borderStrong : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xl
                    }
                    MouseArea {
                        id: dismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hist.dismissed()
                    }
                }
            }
            Text {
                visible: hist.entry && hist.entry.body
                Layout.fillWidth: true
                text: hist.entry ? hist.entry.body : ""
                color: Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: histHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    component NotificationCard: Item {
        id: card
        property var entry
        signal dismiss()
        implicitHeight: cardBg.implicitHeight + 16

        Rectangle {
            id: cardBg
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 14
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            implicitHeight: cardCol.implicitHeight + 24
            radius: 10
            color: card.entry && card.entry.urgency === NotificationUrgency.Critical
                ? Theme.accent.red : Theme.muted
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.95
                shadowBlur: 1.5
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 10
                autoPaddingEnabled: true
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 8
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
                        color: "#f5f5f4"
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
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    implicitWidth: 26; implicitHeight: 26; radius: 13
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
                Layout.fillWidth: true
                spacing: Theme.spacing.sm
                visible: card.entry && card.entry.ref && card.entry.ref.actions && card.entry.ref.actions.length > 0
                Repeater {
                    model: card.entry && card.entry.ref ? card.entry.ref.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        implicitHeight: 26
                        implicitWidth: actText.implicitWidth + 16
                        radius: 4
                        color: actMouse.containsMouse ? "#3b3531" : Theme.bgAlt
                        border.color: Theme.borderStrong; border.width: 1
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: modelData.text
                            color: "#f5f5f4"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                        }
                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { modelData.invoke(); card.dismiss(); }
                        }
                    }
                }
            }
        }

        Timer {
            interval: card.entry && card.entry.ref && card.entry.ref.expireTimeout > 0
                ? card.entry.ref.expireTimeout : 6000
            running: true
            repeat: false
            onTriggered: {
                if (card.entry && card.entry.ref && card.entry.urgency !== NotificationUrgency.Critical)
                    card.dismiss();
            }
        }
    }
}
