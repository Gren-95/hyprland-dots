// The small caps heading that separates groups inside a panel.
import QtQuick
import QtQuick.Layouts

Text {
    Layout.fillWidth: true
    Layout.topMargin: Theme.spacing.sm
    color: Theme.mutedDeep
    font.family: Theme.font
    font.pixelSize: Theme.fontSize.xs
    font.letterSpacing: 1
    font.bold: true
}
