/*
 * Fork of the built-in ksysguard "textonly" face.
 *
 * Differences from upstream:
 *  - the label/value text uses a fixed muted gray instead of the theme's
 *    bright text color;
 *  - related sensors can be grouped into one row (CPU usage + temperature,
 *    GPU usage + VRAM + temperature, RAM used/total, download/upload,
 *    read/write), and used/total pairs render as one value;
 *  - the colored indicator can be hidden; otherwise there is one indicator
 *    per row, not one per sensor;
 *  - network and disk RATE rows (download/upload/read/write) are shown as
 *    a 10-second rolling average. ksystemstats only publishes instantaneous
 *    rates (500ms deltas), so the averaging happens here.
 *
 * SPDX-FileCopyrightText: 2019 Marco Martin <mart@kde.org>
 * SPDX-FileCopyrightText: 2019 David Edmundson <davidedmundson@kde.org>
 * SPDX-FileCopyrightText: 2019 Arjen Hiemstra <ahiemstra@heimr.nl>
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.ksysguard.faces as Faces


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

    readonly property bool groupSensors: root.controller.faceConfiguration.groupSensors ?? false
    readonly property bool showIndicators: root.controller.faceConfiguration.showIndicators ?? true

    // Group consecutive sensors that belong together. The suffix rules match
    // the ksystemstats sensor names used by the top bar; anything else (for
    // example disk/all/usedPercent) stays in its own row.
    function groupKey(id) {
        if (id.endsWith("/usage") || id.endsWith("/temperature")) {
            return id.split("/")[0]
        }
        if (id.endsWith("/usedVram") || id.endsWith("/totalVram")) {
            return id.split("/")[0]
        }
        if (id.endsWith("/used") || id.endsWith("/total")) {
            return id.split("/")[0]
        }
        if (id.endsWith("/download") || id.endsWith("/upload")) {
            return "network"
        }
        if (id.endsWith("/read") || id.endsWith("/write")) {
            return "disk"
        }
        return id
    }

    readonly property var sensorGroups: {
        const ids = root.controller.highPrioritySensorIds
        if (!root.groupSensors) {
            const singles = []
            for (let i = 0; i < ids.length; ++i) {
                singles.push([ids[i]])
            }
            return singles
        }

        const groups = []
        let lastKey = ""
        for (let i = 0; i < ids.length; ++i) {
            const id = ids[i]
            const key = groupKey(id)
            if (groups.length > 0 && key === lastKey && key !== id) {
                groups[groups.length - 1].push(id)
            } else {
                groups.push([id])
                lastKey = key
            }
        }
        return groups
    }

    clip: true

    contentItem: GridLayout {
        id: layout

        columnSpacing: Kirigami.Units.smallSpacing * 2
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
            model: root.sensorGroups

            MutedGroupDelegate {
                sensorIds: modelData
                sensorLabels: root.controller.sensorLabels
                showIndicator: root.showIndicators
                updateRateLimit: root.controller.updateRateLimit
                textFont: root.useSmallFont ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont
                indicatorColor: root.colorSource.map[modelData[0]] ?? "#a8a8a8"
            }
        }
    }
}
