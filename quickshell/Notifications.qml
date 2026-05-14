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
    function dismissAll() {
        for (const e of activeList) if (e.ref) e.ref.dismiss();
        activeList = [];
    }
    function clearHistory() { historyList = []; }

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
            anchors { top: true; right: true }
            margins { top: 40; right: 4 }
            implicitWidth: 380
            implicitHeight: Math.max(1, stackCol.implicitHeight)
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            ColumnLayout {
                id: stackCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
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
                ? "#ef4444" : "#a8a29e"
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
                color: "#1c1917"
            }
        }

        ColumnLayout {
            id: cardCol
            anchors.fill: cardBg
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                IconImage {
                    visible: card.entry && (card.entry.image || card.entry.appIcon)
                    source: card.entry ? (card.entry.image || card.entry.appIcon) : ""
                    implicitSize: 24
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: card.entry ? (card.entry.summary || card.entry.appName) : ""
                        color: "#f5f5f4"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.entry && card.entry.appName && card.entry.summary
                        text: card.entry ? card.entry.appName : ""
                        color: "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    implicitWidth: 26; implicitHeight: 26; radius: 13
                    color: closeMouse.containsMouse ? "#44403c" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"; color: "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 22
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
                color: "#d6d3d1"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: card.entry && card.entry.ref && card.entry.ref.actions && card.entry.ref.actions.length > 0
                Repeater {
                    model: card.entry && card.entry.ref ? card.entry.ref.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        implicitHeight: 22
                        implicitWidth: actText.implicitWidth + 16
                        radius: 4
                        color: actMouse.containsMouse ? "#3b3531" : "#292524"
                        border.color: "#44403c"; border.width: 1
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: modelData.text
                            color: "#f5f5f4"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
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
