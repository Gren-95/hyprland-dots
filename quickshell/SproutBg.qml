// Comic-book upside-down speech bubble. Rounded body with a tail at top
// that points UP toward the bar.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color fillColor: Theme.bgAlt
    property color borderColor: Theme.popupBorder
    property real cornerRadius: 0
    property real borderWidth: 1
    property real tailHeight: 10
    property real tailWidth: 18
    property bool showTail: true
    // Where the tail tip sits horizontally (in local coords). Default: centered.
    property real tailX: width / 2
    readonly property real _tailH: showTail ? tailHeight : 0
    readonly property real _clampedTailX: Math.max(
        cornerRadius + tailWidth / 2,
        Math.min(width - cornerRadius - tailWidth / 2, tailX)
    )

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.borderColor
            strokeWidth: root.borderWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            // Start at top-left, just below the tail area, after the corner radius
            startX: root.cornerRadius
            startY: root._tailH

            // Across the top to the start of the tail
            PathLine { x: root._clampedTailX - root.tailWidth / 2; y: root._tailH }
            // Tail going up to the tip
            PathLine { x: root._clampedTailX; y: 0 }
            // Tail coming back down
            PathLine { x: root._clampedTailX + root.tailWidth / 2; y: root._tailH }
            // Continue across the top to the start of the top-right corner
            PathLine { x: root.width - root.cornerRadius; y: root._tailH }
            // Top-right rounded corner
            PathArc {
                x: root.width
                y: root._tailH + root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Clockwise
            }
            // Right side down
            PathLine { x: root.width; y: root.height - root.cornerRadius }
            // Bottom-right rounded corner
            PathArc {
                x: root.width - root.cornerRadius
                y: root.height
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Clockwise
            }
            // Bottom edge
            PathLine { x: root.cornerRadius; y: root.height }
            // Bottom-left rounded corner
            PathArc {
                x: 0
                y: root.height - root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Clockwise
            }
            // Left side up
            PathLine { x: 0; y: root._tailH + root.cornerRadius }
            // Top-left rounded corner
            PathArc {
                x: root.cornerRadius
                y: root._tailH
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Clockwise
            }
        }
    }
}
