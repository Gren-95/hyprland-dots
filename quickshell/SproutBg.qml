// Popup background with concave top corners + convex bottom corners.
// Path traversed counterclockwise (top-left → bottom-left → bottom-right → top-right → top-left).
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color fillColor: "#1c1917"
    property color borderColor: "#78716c"
    property real cornerRadius: 16
    property real borderWidth: 1

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.borderColor
            strokeWidth: root.borderWidth
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin

            // Start at top, just inside the top-left concave corner
            startX: root.cornerRadius
            startY: 0

            // Top-left CONVEX corner
            PathArc {
                x: 0
                y: root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Counterclockwise
            }
            // Left edge down
            PathLine { x: 0; y: root.height - root.cornerRadius }
            // Bottom-left CONVEX corner: from (0, H-R) to (R, H)
            PathArc {
                x: root.cornerRadius
                y: root.height
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Counterclockwise
            }
            // Bottom edge
            PathLine { x: root.width - root.cornerRadius; y: root.height }
            // Bottom-right CONVEX corner: from (W-R, H) to (W, H-R)
            PathArc {
                x: root.width
                y: root.height - root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Counterclockwise
            }
            // Right edge up
            PathLine { x: root.width; y: root.cornerRadius }
            // Top-right CONVEX corner
            PathArc {
                x: root.width - root.cornerRadius
                y: 0
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
                direction: PathArc.Counterclockwise
            }
            // Top edge back to start (auto-close)
        }
    }
}
