import QtQuick
import Caelestia.Blobs

Item {
    id: root
    property color fillColor: "#1c1917"
    property color borderColor: "#78716c"  // unused; kept for API compatibility
    property real cornerRadius: 14
    property real borderWidth: 1            // unused

    BlobGroup {
        id: blobs
        smoothing: 24
        color: root.fillColor
    }

    BlobRect {
        anchors.fill: parent
        group: blobs
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.cornerRadius
        bottomRightRadius: root.cornerRadius
    }
}
