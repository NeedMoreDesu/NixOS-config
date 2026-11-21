/*
 * One compact row: an optional colored indicator followed by the group's
 * segments. Used/total sensor pairs are collapsed into a single value.
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property var sensorIds: []
    property var sensorLabels: ({})
    property bool showIndicator: true
    property int updateRateLimit
    property font textFont
    property color indicatorColor: "#a8a8a8"

    readonly property var segments: {
        const result = []
        let i = 0
        while (i < root.sensorIds.length) {
            const id = root.sensorIds[i]
            const nextId = i + 1 < root.sensorIds.length ? root.sensorIds[i + 1] : ""
            if (isUsedTotalPair(id, nextId)) {
                result.push([id, nextId])
                i += 2
            } else {
                result.push([id])
                i += 1
            }
        }
        return result
    }

    function isUsedTotalPair(firstId, secondId) {
        if (!firstId || !secondId) {
            return false
        }
        return (firstId.endsWith("/used") && secondId.endsWith("/total"))
            || (firstId.endsWith("/usedVram") && secondId.endsWith("/totalVram"))
    }

    Layout.preferredWidth: implicitWidth
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

    spacing: Kirigami.Units.smallSpacing

    FontMetrics {
        id: fontMetrics
        font: root.textFont
    }

    Rectangle {
        visible: root.showIndicator
        Layout.preferredWidth: Kirigami.Units.smallSpacing
        Layout.preferredHeight: fontMetrics.height
        Layout.alignment: Qt.AlignVCenter
        color: root.indicatorColor
    }

    Repeater {
        model: root.segments

        delegate: MutedSegment {
            sensorIds: modelData
            sensorLabels: root.sensorLabels
            updateRateLimit: root.updateRateLimit
            textFont: root.textFont
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
