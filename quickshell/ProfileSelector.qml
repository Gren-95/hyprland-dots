// Power-profile selector: a segmented control with a sliding highlight under
// the active profile and a one-line description of the highlighted/active one.
// The keyboard-highlighted segment gets an outline.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

ColumnLayout {
    id: ps
    property var profiles: []
    property int activeIndex: 0
    property int highlightedIndex: -1
    signal picked(int index)
    signal hovered(int index)
    spacing: Theme.spacing.md

    function _glyph(p)  { return p === PowerProfile.Performance ? "󱐋"          : p === PowerProfile.Balanced ? "󰾅" : "󰌪" }
    function _label(p)  { return p === PowerProfile.Performance ? "Performance" : p === PowerProfile.Balanced ? "Balanced" : "Saver" }
    function _accent(p) { return p === PowerProfile.Performance ? Theme.accent.red     : p === PowerProfile.Balanced ? Theme.accent.yellow : Theme.accent.green }
    function _desc(p)   { return p === PowerProfile.Performance ? "Maximum speed. Runs hotter and drains the battery."
                               : p === PowerProfile.Balanced    ? "Default. Even power and performance."
                                                                : "Extends battery life by throttling." }

    readonly property int shownIndex: highlightedIndex >= 0 && highlightedIndex < profiles.length ? highlightedIndex : activeIndex

    Rectangle {
        id: track
        Layout.fillWidth: true
        implicitHeight: 60
        radius: 10 * Theme.radiusScale
        color: Theme.bgInset
        border.color: Theme.borderSubtle
        border.width: 1

        readonly property real pad: 4
        readonly property real segW: ps.profiles.length > 0 ? (width - pad * 2) / ps.profiles.length : 0

        // Sliding highlight under the active profile.
        Rectangle {
            id: slider
            y: track.pad
            height: track.height - track.pad * 2
            width: track.segW
            x: track.pad + ps.activeIndex * track.segW
            radius: 8 * Theme.radiusScale
            color: ps.profiles.length > 0 ? ps._accent(ps.profiles[ps.activeIndex]) : Theme.accentPrimary
            Behavior on x { NumberAnimation { duration: Theme.duration.slow; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
        }

        Row {
            anchors.fill: parent
            anchors.margins: track.pad
            Repeater {
                model: ps.profiles
                delegate: Item {
                    id: seg
                    required property var modelData
                    required property int index
                    readonly property bool isActive: ps.activeIndex === index
                    width: track.segW
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        radius: 8 * Theme.radiusScale
                        color: "transparent"
                        border.color: Theme.fg
                        border.width: ps.highlightedIndex === seg.index ? 2 : 0
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 8 * Theme.radiusScale
                        color: segMa.containsMouse && !seg.isActive ? Theme.bgActive : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        scale: segMa.pressed ? 0.92 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: ps._glyph(seg.modelData)
                            color: seg.isActive ? Theme.fgOnAccent : ps._accent(seg.modelData)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xl
                            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: ps._label(seg.modelData)
                            color: seg.isActive ? Theme.fgOnAccent : Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.bold: seg.isActive
                            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                        }
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ps.picked(seg.index)
                        onContainsMouseChanged: if (containsMouse) ps.hovered(seg.index)
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: ps.profiles.length > 0 ? ps._desc(ps.profiles[ps.shownIndex]) : ""
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        wrapMode: Text.WordWrap
    }
}
