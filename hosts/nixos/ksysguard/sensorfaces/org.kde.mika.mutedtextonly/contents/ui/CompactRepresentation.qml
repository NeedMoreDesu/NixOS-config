/*
 * Fork of the built-in ksysguard "textonly" face.
 *
 * Differences from upstream:
 *  - the label/value text uses a fixed muted gray instead of the theme's
 *    bright text color;
 *  - network and disk RATE rows (download/upload/read/write) are shown as
 *    a 60-second rolling average. ksystemstats only publishes instantaneous
 *    rates (500ms deltas), so the averaging happens here, in the delegate.
 *
 * SPDX-FileCopyrightText: 2019 Marco Martin <mart@kde.org>
 * SPDX-FileCopyrightText: 2019 David Edmundson <davidedmundson@kde.org>
 * SPDX-FileCopyrightText: 2019 Arjen Hiemstra <ahiemstra@heimr.nl>
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.faces as Faces
import org.kde.ksysguard.formatter as Formatter

import org.kde.quickcharts as Charts
import org.kde.quickcharts.controls as ChartsControls


Faces.CompactSensorFace {
    id: root

    Layout.minimumWidth: horizontalFormFactor ? Math.max(contentItem.Layout.minimumWidth, defaultMinimumSize) : defaultMinimumSize
    Layout.minimumHeight: verticalFormFactor ? Math.max(contentItem.Layout.minimumHeight, defaultMinimumSize) : defaultMinimumSize
    Layout.preferredWidth: horizontalFormFactor ? contentItem.preferredWidth : -1
    Layout.maximumWidth: horizontalFormFactor ? Math.max(contentItem.preferredWidth, defaultMinimumSize) : -1

    FontMetrics {
        id: defaultMetrics
        font: Kirigami.Theme.defaultFont
    }

    FontMetrics {
        id: smallMetrics
        font: Kirigami.Theme.smallFont
    }

    readonly property bool useSmallFont: (horizontalFormFactor && height < defaultMetrics.lineSpacing + 2) || (verticalFormFactor && width < defaultMetrics.averageCharacterWidth * 6 + Kirigami.Units.smallSpacing)
    readonly property real lineHeight: useSmallFont ? smallMetrics.lineSpacing : defaultMetrics.lineSpacing

    clip: true

    contentItem: GridLayout {
        id: layout

        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: 1

        flow: GridLayout.TopToBottom
        rows: root.verticalFormFactor ? -1 : Math.max(Math.floor(root.height / (root.lineHeight + rowSpacing)), 1)

        property real preferredWidth: {
            if (repeater.count == 0) {
                return 0
            }

            const columns = Math.ceil(repeater.count / rows)
            let width = 0
            for (let i = 0; i < columns; ++i) {
                width += repeater.itemAt(i).Layout.preferredWidth
            }
            width += (columns - 1) * columnSpacing
            return width
        }

        Repeater {
            id: repeater
            model: root.controller.highPrioritySensorIds

            MutedLegendDelegate {
                id: legend

                Layout.fillWidth: true
                Layout.minimumWidth: root.horizontalFormFactor ? minimumWidth : Kirigami.Units.gridUnit
                Layout.preferredWidth: root.horizontalFormFactor ? preferredWidth : minimumWidth
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                readonly property int averageWindowMs: 60000
                readonly property bool averaged: legend.isRateSensor(modelData)
                property var samples: []
                property real averageValue: NaN

                function isRateSensor(id) {
                    if (!id) {
                        return false
                    }
                    return id.endsWith("/download") || id.endsWith("/upload")
                        || id.endsWith("/read") || id.endsWith("/write")
                }

                function sample() {
                    const v = Number(sensor.value)
                    if (!isFinite(v)) {
                        return
                    }
                    const now = Date.now()
                    legend.samples.push({ t: now, v: v })
                    while (legend.samples.length > 0 && now - legend.samples[0].t > legend.averageWindowMs) {
                        legend.samples.shift()
                    }
                    let sum = 0
                    for (let i = 0; i < legend.samples.length; ++i) {
                        sum += legend.samples[i].v
                    }
                    legend.averageValue = sum / legend.samples.length
                }

                name: root.controller.sensorLabels[modelData] || sensor.name
                shortName: root.controller.sensorLabels[modelData] || sensor.shortName
                value: (legend.averaged && isFinite(legend.averageValue))
                    ? Formatter.Formatter.formatValue(legend.averageValue, sensor.unit)
                    : sensor.formattedValue
                color: root.colorSource.map[modelData]
                textColor: "#a8a8a8"

                font: root.useSmallFont ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont

                maximumValueWidth: Formatter.Formatter.maximumLength(sensor.unit, root.useSmallFont ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont)

                ToolTip.visible: false

                Component.onCompleted: contentItem.children[1].opacity = Qt.binding(() => contentItem.children[1].width > 0 ? 1 : 0)

                Sensors.Sensor {
                    id: sensor
                    sensorId: modelData
                    updateRateLimit: root.controller.updateRateLimit
                }

                Timer {
                    interval: 500
                    repeat: true
                    running: legend.averaged
                    triggeredOnStart: true
                    onTriggered: legend.sample()
                }
            }
        }
    }
}