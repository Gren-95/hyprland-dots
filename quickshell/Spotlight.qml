import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0

    readonly property string calcExpr: {
        const q = root.query.trim();
        if (q.startsWith("=")) return q.slice(1).trim();
        // auto-detect: has at least one digit and one operator
        if (/[+\-*/%]/.test(q) && /\d/.test(q) && /^[\d+\-*/.()\s%]+$/.test(q)) return q;
        return "";
    }
    readonly property string calcResult: {
        if (!root.calcExpr) return "";
        try {
            const r = new Function("return (" + root.calcExpr + ")")();
            if (typeof r === "number" && isFinite(r)) {
                return Number.isInteger(r) ? String(r) : String(parseFloat(r.toFixed(10)));
            }
        } catch (e) {}
        return "";
    }
    readonly property bool hasCalc: root.calcResult !== ""

    readonly property var filtered: {
        if (!DesktopEntries.applications) return [];
        const all = DesktopEntries.applications.values || [];
        const q = root.query.toLowerCase();
        return all
            .filter(a => !a.noDisplay)
            .filter(a => {
                if (!q) return true;
                const name = (a.name || "").toLowerCase();
                const gen = (a.genericName || "").toLowerCase();
                const cmt = (a.comment || "").toLowerCase();
                return name.includes(q) || gen.includes(q) || cmt.includes(q);
            })
            .sort((a, b) => {
                if (q) {
                    const an = (a.name || "").toLowerCase();
                    const bn = (b.name || "").toLowerCase();
                    const aStarts = an.startsWith(q) ? 0 : 1;
                    const bStarts = bn.startsWith(q) ? 0 : 1;
                    if (aStarts !== bStarts) return aStarts - bStarts;
                }
                return (a.name || "").localeCompare(b.name || "");
            });
    }

    readonly property int calcOffset: hasCalc ? 1 : 0
    readonly property int totalRows: calcOffset + filtered.length

    function toggle() {
        open = !open;
        if (open) { query = ""; selectedIndex = 0; }
    }
    function openAt(idx) {
        if (!open) { open = true; query = ""; }
        selectedIndex = idx < 0 ? Math.max(0, root.totalRows - 1)
                                : Math.min(idx, Math.max(0, root.totalRows - 1));
    }
    function close() { open = false; }
    function activate(i) {
        if (hasCalc && i === 0) {
            copyProc.command = ["wl-copy", root.calcResult];
            copyProc.startDetached();
            close();
            return;
        }
        const item = filtered[i - calcOffset];
        if (item) item.execute();
        close();
    }

    Process { id: copyProc; command: [] }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Dim backdrop
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.45
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            // Centered search card
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.22)
                width: 640
                height: Math.min(560, headerCol.implicitHeight + resultsCol.implicitHeight + 28)
                radius: 14
                color: Theme.bgAlt
                border.color: Theme.mutedDeep
                border.width: 1
                scale: root.open ? 1.0 : 0.96
                opacity: root.open ? 1.0 : 0.0
                Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                focus: root.open
                Keys.onPressed: (e) => {
                    const n = root.totalRows;
                    if (e.key === Qt.Key_Escape) {
                        root.close(); e.accepted = true;
                    } else if (e.key === Qt.Key_Down) {
                        if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up) {
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.activate(root.selectedIndex); e.accepted = true;
                    } else if (e.key === Qt.Key_Backspace) {
                        root.query = root.query.slice(0, -1);
                        root.selectedIndex = 0;
                        e.accepted = true;
                    } else if (e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32) {
                        root.query += e.text;
                        root.selectedIndex = 0;
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: headerCol
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Text {
                            text: "󰍉"
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 30
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.query || "Spotlight Search"
                            color: root.query ? Theme.fg : Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: 24
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }
                }

                Flickable {
                    id: results
                    anchors {
                        top: headerCol.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        topMargin: 6
                        leftMargin: 8
                        rightMargin: 8
                        bottomMargin: 8
                    }
                    contentHeight: resultsCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: resultsCol
                        width: parent.width
                        spacing: 2

                        CalcRow {
                            visible: root.hasCalc
                            expr: root.calcExpr
                            result: root.calcResult
                            highlighted: root.selectedIndex === 0
                            Layout.fillWidth: true
                            onPicked: root.activate(0)
                            onHovered: root.selectedIndex = 0
                        }

                        Repeater {
                            model: root.filtered.slice(0, 60)
                            delegate: SpotlightRow {
                                required property var modelData
                                required property int index
                                entry: modelData
                                highlighted: root.selectedIndex === (index + root.calcOffset)
                                Layout.fillWidth: true
                                onPicked: root.activate(index + root.calcOffset)
                                onHovered: root.selectedIndex = index + root.calcOffset
                            }
                        }
                    }
                }
            }
        }
    }

    component CalcRow: Rectangle {
        id: crow
        property string expr: ""
        property string result: ""
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 60
        radius: 8
        color: crow.highlighted ? "#3b3531" : (cHover.containsMouse ? "#262220" : "transparent")
        border.color: Theme.accent.blue
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 14
            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 6
                color: "#1d4ed8"
                Text {
                    anchors.centerIn: parent
                    text: "="
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 20
                    font.bold: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: crow.result
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: crow.expr + " ="
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            Text {
                text: "↵ Copy"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
        MouseArea {
            id: cHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: crow.picked()
            onContainsMouseChanged: if (containsMouse) crow.hovered()
        }
    }

    component SpotlightRow: Rectangle {
        id: row
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 52
        radius: 8
        color: row.highlighted ? "#3b3531" : (hover.containsMouse ? "#262220" : "transparent")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 14
            IconImage {
                implicitSize: 36
                source: row.entry ? Quickshell.iconPath(row.entry.icon, "application-x-executable") : ""
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: row.entry ? row.entry.name : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.bold: row.highlighted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    visible: row.entry && row.entry.comment
                    text: row.entry ? row.entry.comment : ""
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            Text {
                visible: row.highlighted
                text: "↵"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: 14
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.picked()
            onContainsMouseChanged: if (containsMouse) row.hovered()
        }
    }
}
