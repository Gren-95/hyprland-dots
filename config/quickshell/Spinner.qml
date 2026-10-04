// Small indeterminate loading spinner — a rotating 280° arc. Used in list rows
// for transient busy states (Wi-Fi connecting, Bluetooth pairing).
import QtQuick
import QtQuick.Shapes

Item {
    id: s
    property color color: Theme.accent.yellow
    property real lineWidth: 2
    implicitWidth: 14
    implicitHeight: 14

    Shape {
        id: shp
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: s.color
            strokeWidth: s.lineWidth
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: s.width / 2
                centerY: s.height / 2
                radiusX: (s.width - s.lineWidth) / 2
                radiusY: (s.height - s.lineWidth) / 2
                startAngle: -90
                sweepAngle: 280
                moveToStart: true
            }
        }
    }

    // Only spin while actually shown, to avoid burning frames off-screen.
    RotationAnimator {
        target: shp
        from: 0
        to: 360
        duration: 750
        loops: Animation.Infinite
        running: s.visible
    }
}
