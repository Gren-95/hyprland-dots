// Rounded container holding TabPill children. Used in the bar popups that
// have a tab strip header (Connectivity, AudioPower).
//
// `tabs` is an array of { glyph, label, accent, id } objects. `activeId` says
// which pill is highlighted. Pills emit `picked(id)` when clicked.
//
// A single accent-tinted indicator glides between pills (with a slight
// overshoot) rather than each pill cross-fading its own background — this
// reads as one moving object and keeps the active accent colour continuous.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: strip
    property var tabs: []
    property string activeId: ""
    signal picked(string id)

    readonly property int tabCount: tabs.length
    readonly property int activeIndex: {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].id === activeId) return i;
        return 0;
    }
    readonly property color activeAccent: tabCount > 0 ? tabs[activeIndex].accent : Theme.accent.blue

    Layout.preferredHeight: Theme.height.control
    radius: 15 * Theme.radiusScale
    color: Theme.bgDeep
    border.color: Theme.border
    border.width: 1

    // Sliding selection indicator — the only piece that carries the accent.
    Rectangle {
        id: indicator
        visible: strip.tabCount > 0
        y: 2
        height: parent.height - 4
        width: strip.tabCount > 0 ? (parent.width - 4) / strip.tabCount : 0
        x: 2 + strip.activeIndex * width
        radius: 13 * Theme.radiusScale
        color: Qt.rgba(strip.activeAccent.r, strip.activeAccent.g, strip.activeAccent.b, 0.20)
        border.color: strip.activeAccent
        border.width: 1
        Behavior on x           { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
        Behavior on color       { ColorAnimation  { duration: Theme.duration.normal } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }
    }

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
