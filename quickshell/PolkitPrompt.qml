// Polkit authentication agent. Replaces hyprpolkitagent — registers as the
// session's polkit agent and renders a centered prompt when authentication
// is required (sudo, mount, suspend, etc.).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

Scope {
    id: root

    PolkitAgent {
        id: agent
        path: "/org/quickshell/PolicyKit1/AuthenticationAgent"
    }

    readonly property var flow: agent.flow
    readonly property bool active: agent.isActive

    // Buffered password input — owned at root so the submit/cancel functions
    // can read it without poking into the per-screen delegate.
    property string password: ""

    function _submit() {
        if (!flow) return;
        flow.submit(root.password);
        root.password = "";
    }
    function _cancel() {
        if (flow) flow.cancelAuthenticationRequest();
        root.password = "";
    }

    Connections {
        target: agent
        function onAuthenticationRequestStarted() {
            root.password = "";
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.65
            }

            FocusScope {
                id: cardFocus
                anchors.centerIn: parent
                width: 500
                height: cardCol.implicitHeight + 32
                focus: root.active

                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root._cancel(); e.accepted = true; }
                }

                Rectangle {
                    id: card
                    anchors.fill: parent
                    radius: 14
                    color: Theme.bg
                    border.color: Theme.mutedDeep
                    border.width: 1
                }

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 20
                    }
                    spacing: 14

                    // Header: icon + title
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: "󰒃"
                            color: Theme.accent.purple
                            font.family: Theme.font
                            font.pixelSize: 30
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "Authentication required"
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Text {
                                visible: root.flow && root.flow.actionId
                                text: root.flow ? root.flow.actionId : ""
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                    // Action message
                    Text {
                        Layout.fillWidth: true
                        text: root.flow ? root.flow.message : ""
                        color: Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }

                    // Identity selector (only when multiple identities)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.flow && root.flow.identities && root.flow.identities.length > 1
                        Text {
                            text: "Identity"
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.flow && root.flow.selectedIdentity
                                ? (root.flow.selectedIdentity.pretty || root.flow.selectedIdentity.toString())
                                : ""
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }

                    // Password input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 8
                        color: "#0c0a09"
                        border.color: passwordField.activeFocus ? Theme.accent.purple : Theme.border
                        border.width: 1
                        visible: root.flow && root.flow.isResponseRequired

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 15
                            echoMode: root.flow && root.flow.responseVisible
                                ? TextInput.Normal
                                : TextInput.Password
                            passwordCharacter: "•"
                            selectByMouse: true
                            focus: true
                            text: root.password
                            onTextChanged: if (text !== root.password) root.password = text
                            onAccepted: root._submit()
                        }
                        // Re-focus this field whenever the prompt becomes visible
                        Connections {
                            target: root
                            function onActiveChanged() {
                                if (root.active) focusDelay.restart();
                            }
                        }
                        Timer {
                            id: focusDelay
                            interval: 80
                            repeat: false
                            onTriggered: passwordField.forceActiveFocus()
                        }
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            visible: passwordField.text.length === 0 && !passwordField.activeFocus
                            text: {
                                if (!root.flow) return "Password";
                                const p = (root.flow.inputPrompt || "").trim();
                                return p.endsWith(":") ? p.slice(0, -1) : (p || "Password");
                            }
                            color: Theme.disabled
                            font.family: Theme.font
                            font.pixelSize: 15
                        }
                    }

                    // Supplementary / error message
                    Text {
                        Layout.fillWidth: true
                        visible: root.flow && root.flow.supplementaryMessage
                        text: root.flow ? root.flow.supplementaryMessage : ""
                        color: root.flow && root.flow.supplementaryIsError ? "#f87171" : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 10

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: cancelBtn
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 32
                            radius: 8
                            color: cancelMouse.containsMouse ? Theme.border : "transparent"
                            border.color: Theme.border
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.fgMuted
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._cancel()
                            }
                        }

                        Rectangle {
                            id: okBtn
                            Layout.preferredWidth: 110
                            Layout.preferredHeight: 32
                            radius: 8
                            color: okMouse.containsMouse ? "#7c3aed" : Theme.accent.purple
                            Text {
                                anchors.centerIn: parent
                                text: "Authenticate"
                                color: "#0a0a0a"
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.bold: true
                            }
                            MouseArea {
                                id: okMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._submit()
                            }
                        }
                    }
                }
            }
        }
    }
}
