// A Quick Actions item promoted to the bar ("Bar" in the Settings Bar tab).
// First-class bar icon:
//  - toggles render live state: accent-tinted glyph + a dot underneath
//    while on, off-glyph in muted grey while off
//  - one-shots light up in their accent on hover
//  - left-click activates (toggle flip / one-shot fire)
//  - right-click opens the full Quick Actions panel anchored at this icon
import QtQuick
import QtQuick.Layouts

Item {
    id: qi
    property var entry            // { glyph, offGlyph?, label, accent, action }
    property var actions          // the QuickActions module instance
    property var parentBar: null
    readonly property bool isToggle: actions && entry ? actions.isToggleAction(entry.action) : false
    readonly property bool on: isToggle && actions.toggleState(entry.action)

    Layout.fillHeight: true
    implicitWidth: 26
    scale: ma.pressed ? 0.88 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Subtle hover surface, matching BarIcon.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius.sm
        color: ma.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    }

    Text {
        anchors.centerIn: parent
        text: qi.isToggle && !qi.on ? (qi.entry.offGlyph || qi.entry.glyph) : (qi.entry ? qi.entry.glyph : "")
        color: qi.on || ma.containsMouse ? qi.entry.accent : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.md
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    }

    // On-state dot — mirrors the panel's switch state at a glance.
    Rectangle {
        visible: qi.isToggle && qi.on
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        width: 4; height: 4; radius: 2 * Theme.radiusScale
        color: qi.entry ? qi.entry.accent : Theme.accentPrimary
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!qi.actions || !qi.entry) return;
            if (e.button === Qt.RightButton) {
                // The escape hatch back to the full panel, hanging from
                // this icon — works even when the chevron itself is hidden.
                qi.actions._openAnchor = qi;
                qi.actions.popupOpen = true;
            } else {
                qi.actions.performAction(qi.entry.action, qi);
            }
        }
    }

    BarTooltip {
        bar: qi.parentBar
        target: qi
        text: (qi.entry ? qi.entry.label : "")
              + (qi.isToggle ? (qi.on ? " · on" : " · off") : "")
              + " · right-click: all actions"
        active: ma.containsMouse && !(qi.actions && qi.actions.popupOpen)
    }
}
