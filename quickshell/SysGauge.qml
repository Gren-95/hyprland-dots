// Progress ring for the system monitor: a track plus a coloured arc that
// glides to each new value and crossfades when the threshold colour changes.
// `centerText` / `subText` render inside the ring.
import QtQuick
import QtQuick.Shapes

Item {
    id: gauge

    property real value: 0
    property real maxValue: 100
    property color color: Theme.accent.green
    property string centerText: ""
    property string subText: ""
    property real size: 96
    property real thickness: 8
    property int centerFontSize: Theme.fontSize.xl

    readonly property real fraction: maxValue > 0 ? Math.max(0, Math.min(1, value / maxValue)) : 0

    // Animated copy of the fraction so the arc moves instead of snapping.
    property real shownFraction: 0
    Behavior on shownFraction { NumberAnimation { duration: Theme.duration.slow * 3; easing.type: Theme.easing.standard } }
    onFractionChanged: shownFraction = fraction
    Component.onCompleted: shownFraction = fraction

    implicitWidth: size
    implicitHeight: size

    Shape {
        id: ring
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        readonly property real cx: width / 2
        readonly property real r: width / 2 - gauge.thickness / 2 - 1

        ShapePath {
            strokeColor: Theme.bgInset
            strokeWidth: gauge.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.cx; centerY: ring.cx; radiusX: ring.r; radiusY: ring.r; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: gauge.color
            strokeWidth: gauge.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            Behavior on strokeColor { ColorAnimation { duration: Theme.duration.slow } }
            PathAngleArc {
                centerX: ring.cx; centerY: ring.cx; radiusX: ring.r; radiusY: ring.r
                startAngle: -90
                sweepAngle: Math.max(0.01, 360 * gauge.shownFraction)
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: gauge.centerText
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: gauge.centerFontSize
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: gauge.subText !== ""
            text: gauge.subText
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
    }
}
