// History graph for the system monitor, btop style: a filled area under a
// bright line, over faint grid lines. `values` holds the samples, oldest
// first; the newest sits at the right edge. `mirror` draws from the top
// down, for the upload half of a network graph.
import QtQuick
import QtQuick.Shapes

Item {
    id: graph

    property var values: []
    property real maxValue: 100      // <= 0 scales to the largest sample
    property real floorMax: 1        // lower bound for the auto scale
    property color color: Theme.accent.green
    property bool mirror: false
    property int samples: 60
    // When > 0, each new sample slides the line left over this many
    // milliseconds instead of jumping, so the graph scrolls continuously.
    property int scrollMs: 0
    property real shift: 0
    readonly property real step: width / (samples - 1)
    onValuesChanged: {
        shiftAnim.stop();
        if (scrollMs > 0 && values.length > 1) {
            shift = step;
            shiftAnim.duration = scrollMs;
            shiftAnim.start();
        } else {
            shift = 0;
        }
    }
    NumberAnimation { id: shiftAnim; target: graph; property: "shift"; to: 0 }

    implicitHeight: 96
    clip: true

    readonly property real scaleMax: {
        if (maxValue > 0) return maxValue;
        let m = floorMax;
        for (let i = 0; i < values.length; i++) if (values[i] > m) m = values[i];
        return m;
    }
    readonly property var line: {
        const w = width, h = height, n = values.length;
        if (w <= 0 || h <= 0) return [];
        const pts = [];
        for (let i = 0; i < samples; i++) {
            const idx = i - (samples - n);
            const f = idx >= 0 ? Math.max(0, Math.min(1, values[idx] / scaleMax)) : 0;
            pts.push(Qt.point(i * step + shift, mirror ? f * h : h - f * h));
        }
        return pts;
    }
    readonly property var area: {
        const base = mirror ? 0 : height;
        if (line.length === 0) return [];
        return [Qt.point(line[0].x, base)].concat(line, [Qt.point(line[line.length - 1].x, base)]);
    }

    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            width: graph.width
            height: 1
            y: Math.round(graph.height * (index + 1) / 4)
            color: Theme.alpha(Theme.fg, 0.06)
        }
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 0; y1: graph.mirror ? graph.height : 0
                x2: 0; y2: graph.mirror ? 0 : graph.height
                GradientStop { position: 0.0; color: Theme.alpha(graph.color, 0.38) }
                GradientStop { position: 1.0; color: Theme.alpha(graph.color, 0.03) }
            }
            PathPolyline { path: graph.area }
        }
        ShapePath {
            strokeColor: graph.color
            strokeWidth: 2
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            Behavior on strokeColor { ColorAnimation { duration: Theme.duration.slow } }
            PathPolyline { path: graph.line }
        }
    }
}
