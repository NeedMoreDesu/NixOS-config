/*
 * One metric inside a compact row. A segment is either a single sensor or a
 * used/total pair (e.g. VRAM used + VRAM total), rendered as one value.
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.formatter as Formatter

Row {
    id: root

    property var sensorIds: []
    property var sensorLabels: ({})
    property font textFont
    property int updateRateLimit
    property int averageWindowMs: 10000
    property color textColor: "#a8a8a8"

    readonly property bool paired: sensorIds.length > 1
    readonly property string labelText: sensorLabels[sensorIds[0]] ?? ""
    readonly property bool averaged: !paired && isRateSensor(sensorIds[0])

    property var samples: []
    property real averageValue: NaN

    onSensorIdsChanged: {
        samples = []
        averageValue = NaN
    }

    spacing: Kirigami.Units.smallSpacing

    TextMetrics {
        id: pairMetrics
        font: root.textFont
        text: "1023.9 / 1023.9 GiB"
    }

    TextMetrics {
        id: temperatureMetrics
        font: root.textFont
        text: "999 °C"
    }

    readonly property real maximumValueWidth: {
        const unit = root.paired ? second.unit : first.unit
        if (root.paired) {
            return pairMetrics.advanceWidth
        }
        const maxLength = Formatter.Formatter.maximumLength(unit, root.textFont)
        if (maxLength > 0) {
            return maxLength
        }
        return temperatureMetrics.advanceWidth
    }

    function isRateSensor(id) {
        if (!id) {
            return false
        }
        return id.endsWith("/download") || id.endsWith("/upload")
            || id.endsWith("/read") || id.endsWith("/write")
    }

    function sample() {
        const value = Number(first.value)
        if (!isFinite(value)) {
            return
        }
        const now = Date.now()
        root.samples.push({ t: now, v: value })
        while (root.samples.length > 0 && now - root.samples[0].t > root.averageWindowMs) {
            root.samples.shift()
        }
        let sum = 0
        for (let i = 0; i < root.samples.length; ++i) {
            sum += root.samples[i].v
        }
        root.averageValue = sum / root.samples.length
    }

    function formatNumberPart(value, unit) {
        const text = Formatter.Formatter.formatValueWithPrecision(value, unit, 1)
        if (!text || text.length === 0) {
            return "0"
        }
        return text.replace(/\s+\S+$/, "")
    }

    function formatPair(used, total, unit) {
        const totalText = Formatter.Formatter.formatValueWithPrecision(total, unit, 1)
        const totalPart = totalText && totalText.length > 0 ? totalText : "0"
        return formatNumberPart(used, unit) + " / " + totalPart
    }

    readonly property string valueText: {
        if (root.paired) {
            return root.formatPair(first.value, second.value, first.unit)
        }
        if (root.averaged && isFinite(root.averageValue)) {
            return Formatter.Formatter.formatValue(root.averageValue, first.unit)
        }
        return first.formattedValue
    }

    Label {
        visible: root.labelText.length > 0
        text: root.labelText
        font: root.textFont
        color: root.textColor
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
    }

    Label {
        width: Math.max(root.maximumValueWidth, implicitWidth)
        text: root.valueText
        font: root.textFont
        color: root.textColor
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }

    Sensors.Sensor {
        id: first
        sensorId: root.sensorIds.length > 0 ? root.sensorIds[0] : ""
        updateRateLimit: root.updateRateLimit
    }

    Sensors.Sensor {
        id: second
        sensorId: root.sensorIds.length > 1 ? root.sensorIds[1] : ""
        updateRateLimit: root.updateRateLimit
    }

    Timer {
        interval: 500
        repeat: true
        running: root.averaged
        triggeredOnStart: true
        onTriggered: root.sample()
    }
}
