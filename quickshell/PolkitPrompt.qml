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

    function _submit() {
        if (!flow) return;
        flow.submit(passwordField.text);
        passwordField.text = "";
    }
    function _cancel() {
        if (flow) flow.cancelAuthenticationRequest();
        passwordField.text = "";
    }

    // Clear the password input whenever a new request comes in
    Connections {
        target: agent
        function onAuthenticationRequestStarted() {
            passwordField.text = "";
            passwordField.forceActiveFocus();
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

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 440
                height: cardCol.implicitHeight + 32
                radius: 14
                color: "#1c1917"
                border.color: "#78716c"
                border.width: 1
                focus: root.active

                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root._cancel(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root._submit(); e.accepted = true;
                    }
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
                            color: "#a78bfa"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 28
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "Authentication required"
                                color: "#fafaf9"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                visible: root.flow && root.flow.actionId
                                text: root.flow ? root.flow.actionId : ""
                                color: "#78716c"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3633" }

                    // Action message
                    Text {
                        Layout.fillWidth: true
                        text: root.flow ? root.flow.message : ""
                        color: "#d6d3d1"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    // Identity selector (only when multiple identities)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.flow && root.flow.identities && root.flow.identities.length > 1
                        Text {
                            text: "Identity"
                            color: "#a8a29e"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.flow && root.flow.selectedIdentity
                                ? (root.flow.selectedIdentity.pretty || root.flow.selectedIdentity.toString())
                                : ""
                            color: "#fafaf9"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    // Password input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 8
                        color: "#0c0a09"
                        border.color: passwordField.activeFocus ? "#a78bfa" : "#3a3633"
                        border.width: 1
                        visible: root.flow && root.flow.isResponseRequired

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#fafaf9"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 13
                            echoMode: root.flow && root.flow.responseVisible
                                ? TextInput.Normal
                                : TextInput.Password
                            passwordCharacter: "•"
                            selectByMouse: true
                            focus: true
                            onAccepted: root._submit()
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
                            color: "#57534e"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 13
                        }
                    }

                    // Supplementary / error message
                    Text {
                        Layout.fillWidth: true
                        visible: root.flow && root.flow.supplementaryMessage
                        text: root.flow ? root.flow.supplementaryMessage : ""
                        color: root.flow && root.flow.supplementaryIsError ? "#f87171" : "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
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
                            color: cancelMouse.containsMouse ? "#3a3633" : "transparent"
                            border.color: "#3a3633"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: "#d6d3d1"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
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
                            color: okMouse.containsMouse ? "#7c3aed" : "#a78bfa"
                            Text {
                                anchors.centerIn: parent
                                text: "Authenticate"
                                color: "#0a0a0a"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
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
