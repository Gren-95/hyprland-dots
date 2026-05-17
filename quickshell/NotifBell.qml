import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

Item {
    id: bell
    property var parentBar
    property var notifs: null
    // tabIndex: 0 = DnD button, 1 = Clear button, 2+ = history[tabIndex-2]
    property int tabIndex: 0
    readonly property int tabStopCount: notifs ? 2 + notifs.historyList.length : 2
    readonly property int selectedIndex: bell.tabIndex >= 2 ? bell.tabIndex - 2 : -1
    signal navigateNext()
    signal navigatePrev()
    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 14

    function cycleTab(delta) {
        const n = bell.tabStopCount;
        if (n <= 0) return;
        bell.tabIndex = (bell.tabIndex + delta + n) % n;
    }
    function openAt(idx) {
        if (!notifs) return;
        notifs.openCenter();
        const n = bell.tabStopCount;
        bell.tabIndex = idx < 0 ? Math.max(0, n - 1) : Math.min(idx, Math.max(0, n - 1));
    }

    Connections {
        target: bell.notifs
        function onCenterOpenChanged() { if (bell.notifs && bell.notifs.centerOpen) bell.tabIndex = 0 }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Text {
            text: bell.notifs && bell.notifs.dnd ? "󰂛"
                : (bell.notifs && bell.notifs.unreadCount > 0 ? "󰂞" : "󰂚")
            color: bell.notifs && bell.notifs.dnd ? Theme.accent.orange : "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: 14
        }
        Rectangle {
            visible: bell.notifs && bell.notifs.unreadCount > 0 && !bell.notifs.dnd
            implicitWidth: cnt.implicitWidth + 8
            implicitHeight: 14
            radius: 7
            color: Theme.accent.red
            Text {
                id: cnt
                anchors.centerIn: parent
                text: bell.notifs ? String(bell.notifs.unreadCount) : "0"
                color: "#f5f5f4"
                font.family: Theme.font
                font.pixelSize: 10
                font.bold: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!bell.notifs) return;
            if (e.button === Qt.RightButton) {
                bell.notifs.dnd = !bell.notifs.dnd;
            } else {
                bell.notifs.toggleCenter();
            }
        }
    }

    PopupWindow {
        id: centerPop
        anchor.window: bell.parentBar
        anchor.item: bell
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 0
        implicitWidth: 380
        implicitHeight: Math.min(560, centerCol.implicitHeight + 24)
        visible: bell.notifs ? bell.notifs.centerOpen : false
        color: "transparent"

        SproutBg { anchors.fill: parent; fillColor: Theme.bgAlt; borderColor: Theme.mutedDeep; tailX: width / 2 }
        Item {
            anchors.fill: parent
            focus: bell.notifs ? bell.notifs.centerOpen : false
            Keys.onPressed: (e) => {
                if (!bell.notifs) return;
                const n = bell.notifs.historyList.length;
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Escape) {
                    bell.notifs.closeCenter();
                    e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    bell.navigateNext();
                    e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    bell.navigatePrev();
                    e.accepted = true;
                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                    bell.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    bell.cycleTab(-1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (bell.tabIndex === 0) bell.notifs.dnd = !bell.notifs.dnd;
                    else if (bell.tabIndex === 1) bell.notifs.clearHistory();
                    else {
                        const entry = bell.notifs.historyList[bell.selectedIndex];
                        if (entry) bell.notifs.dismissHistoryEntry(entry.id);
                    }
                    e.accepted = true;
                } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    if (n > 0) bell.tabIndex = bell.tabIndex < 2 ? 2 :
                        (bell.selectedIndex + 1 < n ? bell.tabIndex + 1 : 2);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    if (n > 0) bell.tabIndex = bell.tabIndex < 2 ? 2 :
                        (bell.selectedIndex > 0 ? bell.tabIndex - 1 : 1 + n);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                    if (n > 0 && bell.selectedIndex >= 0) {
                        const entry = bell.notifs.historyList[bell.selectedIndex];
                        if (entry) bell.notifs.dismissHistoryEntry(entry.id);
                        if (bell.selectedIndex >= bell.notifs.historyList.length)
                            bell.tabIndex = Math.max(1, 1 + bell.notifs.historyList.length);
                    }
                    e.accepted = true;
                }
            }

            ColumnLayout {
                id: centerCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PinButton {
                        pinned: bell.notifs ? bell.notifs.pinned : false
                        onToggled: if (bell.notifs) bell.notifs.pinned = !bell.notifs.pinned
                    }
                    Text {
                        text: "󰂚  Notifications"
                        color: "#f5f5f4"
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    BtToggle {
                        label: bell.notifs && bell.notifs.dnd ? "DnD on" : "DnD off"
                        active: !!(bell.notifs && bell.notifs.dnd)
                        highlighted: bell.tabIndex === 0
                        onClicked: { bell.tabIndex = 0; if (bell.notifs) bell.notifs.dnd = !bell.notifs.dnd }
                    }
                    BtToggle {
                        label: "Clear"
                        active: false
                        highlighted: bell.tabIndex === 1
                        onClicked: { bell.tabIndex = 1; if (bell.notifs) bell.notifs.clearHistory() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderStrong
                }

                Text {
                    Layout.fillWidth: true
                    visible: bell.notifs && bell.notifs.historyList.length === 0
                    text: "No notifications"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: bell.notifs && bell.notifs.historyList.length > 0
                    Repeater {
                        model: bell.notifs ? bell.notifs.historyList : []
                        delegate: Rectangle {
                            id: hrow
                            required property var modelData
                            required property int index
                            readonly property var entry: modelData
                            readonly property bool highlighted: bell.selectedIndex === hrow.index
                            Layout.fillWidth: true
                            implicitHeight: hcol.implicitHeight + 16
                            radius: 6
                            color: hrow.highlighted ? "#3b3531" : (hoverArea.containsMouse ? Theme.bgAlt : "transparent")

                            ColumnLayout {
                                id: hcol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    IconImage {
                                        visible: hrow.entry && (hrow.entry.image || hrow.entry.appIcon)
                                        source: hrow.entry ? (hrow.entry.image || hrow.entry.appIcon) : ""
                                        implicitSize: 16
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: hrow.entry ? (hrow.entry.summary || hrow.entry.appName) : ""
                                        color: "#f5f5f4"
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: hrow.entry ? Qt.formatTime(hrow.entry.time, "HH:mm") : ""
                                        color: Theme.muted
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                    }
                                    Rectangle {
                                        implicitWidth: 18; implicitHeight: 18; radius: 9
                                        color: xMouse.containsMouse ? Theme.borderStrong : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            color: Theme.muted
                                            font.family: Theme.font
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            id: xMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (bell.notifs) bell.notifs.dismissHistoryEntry(hrow.entry.id)
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: hrow.entry && hrow.entry.body !== ""
                                    text: hrow.entry ? hrow.entry.body : ""
                                    color: Theme.fgMuted
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: hoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                onClicked: {}
                                onContainsMouseChanged: if (containsMouse) bell.tabIndex = hrow.index + 2
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: bell.notifs && bell.notifs.centerOpen && !bell.notifs.pinned
        windows: [centerPop]
        onCleared: if (bell.notifs) bell.notifs.closeCenter()
    }
}
