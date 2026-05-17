// Post-capture action modal: opens after a screenshot is saved.
// Shows a thumbnail of the capture + 4 actions: Edit, OCR, Reveal, Done.
// Auto-dismisses on action invoke; Esc / click-outside closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool open: false
    property string path: ""

    function show(filePath) {
        path = filePath || "";
        if (!path) return;
        open = true;
    }
    function close() { open = false; }

    Process { id: actProc; command: [] }
    function runAction(cmd) {
        actProc.command = cmd;
        actProc.startDetached();
        close();
    }

    PopupCard {
        open: root.open
        cardWidth: 480
        cardHeight: 360
        onClosed: root.close()
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
            else if (e.key === Qt.Key_E) { editBtn.activate(); e.accepted = true; }
            else if (e.key === Qt.Key_O) { ocrBtn.activate();  e.accepted = true; }
            else if (e.key === Qt.Key_R) { revealBtn.activate(); e.accepted = true; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                editBtn.activate(); e.accepted = true;
            }
        }
        contentComponent: Component {
            Item {
                ColumnLayout {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: Theme.spacing.lg
                    }
                    spacing: Theme.spacing.md

                    Text {
                        Layout.fillWidth: true
                        text: "Screenshot saved"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Thumbnail preview.
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 320
                        implicitHeight: 180
                        radius: 8
                        color: Theme.bgDeep
                        border.color: Theme.borderSubtle
                        border.width: 1
                        clip: true
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: root.path ? "file://" + root.path : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            sourceSize.width: 640
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.path
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.sm
                        spacing: Theme.spacing.sm
                        ActionBtn {
                            id: editBtn
                            glyph: "󰏘"; label: "Edit"
                            accent: Theme.accent.blue
                            onActivated: root.runAction(["swappy", "-f", root.path])
                        }
                        ActionBtn {
                            id: ocrBtn
                            glyph: "󰗋"; label: "OCR"
                            accent: Theme.accent.purple
                            onActivated: root.runAction(["bash",
                                Quickshell.env("HOME") + "/.config/scripts/screenshot-ocr.sh",
                                root.path])
                        }
                        ActionBtn {
                            id: revealBtn
                            glyph: "󰉋"; label: "Reveal"
                            accent: Theme.accent.yellow
                            onActivated: root.runAction(["nautilus", root.path])
                        }
                        ActionBtn {
                            glyph: "󰅖"; label: "Done"
                            accent: Theme.accent.green
                            onActivated: root.close()
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: -4
                        text: "E edit · O ocr · R reveal · Esc done"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    component ActionBtn: Rectangle {
        id: btn
        property string glyph: ""
        property string label: ""
        property color accent: Theme.accent.blue
        signal activated()
        function activate() { activated() }

        Layout.fillWidth: true
        implicitHeight: 60
        radius: 8
        color: hover.containsMouse
            ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
            : Theme.bgDeep
        border.color: hover.containsMouse ? accent : Theme.borderSubtle
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: btn.glyph
                color: btn.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: btn.label
                color: hover.containsMouse ? Theme.fg : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activate()
        }
    }
}
