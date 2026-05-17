// Rounded container holding TabPill children. Used in the bar popups that
// have a tab strip header (Connectivity, AudioPower).
//
// `tabs` is an array of { glyph, label, accent, id } objects. `activeId` says
// which pill is highlighted. Pills emit `picked(id)` when clicked.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: strip
    property var tabs: []
    property string activeId: ""
    signal picked(string id)

    Layout.preferredHeight: Theme.height.control
    radius: 15
    color: Theme.bgDeep
    border.color: Theme.border
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0
        Repeater {
            model: strip.tabs
            delegate: TabPill {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: modelData.glyph
                label: modelData.label
                active: strip.activeId === modelData.id
                accent: modelData.accent
                onPicked: strip.picked(modelData.id)
            }
        }
    }
}
