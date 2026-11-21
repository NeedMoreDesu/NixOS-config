/*
 * Panel stat: charge of every connected Bluetooth device, labelled by type
 * (K keyboard, M mouse, H headphones/headset, ...). The data comes from
 * contents/tools/bt-battery.sh, which intersects BlueZ's connected devices
 * with UPower's battery levels. No D-Bus subscription: a 30 s timer re-runs
 * the script, which is cheap and always reflects the current connected set.
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    readonly property color textColor: "#a8a8a8"

    property string output: ""
    readonly property var devices: {
        if (output.length === 0) {
            return []
        }
        const rows = []
        const lines = output.split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const fields = lines[i].split("\t")
            if (fields.length < 3) {
                continue
            }
            rows.push({ type: fields[0], charge: fields[1], name: fields[2] })
        }
        return rows
    }

    readonly property string scriptPath: {
        const url = Qt.resolvedUrl("../tools/bt-battery.sh").toString()
        return decodeURIComponent(url.replace(/^file:\/\//, ""))
    }

    function refresh() {
        const command = "bash " + scriptPath
        batterySource.disconnectSource(command)
        batterySource.connectSource(command)
    }

    Plasmoid.title: "Bluetooth Battery"
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipSubText: root.devices.length === 0
        ? "No Bluetooth battery levels"
        : root.devices.map(device => device.name + ": " + device.charge + "%").join("\n")

    compactRepresentation: Item {
        // The panel sizes applets from the Layout attached properties, not
        // from implicitWidth. Without these the item keeps its initial width
        // (empty output -> 0) and the row spills over the neighbour.
        Layout.minimumWidth: compactRow.implicitWidth
        Layout.preferredWidth: compactRow.implicitWidth
        Layout.maximumWidth: compactRow.implicitWidth
        Layout.fillWidth: false

        implicitWidth: compactRow.implicitWidth
        implicitHeight: compactRow.implicitHeight

        Row {
            id: compactRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Kirigami.Units.smallSpacing * 2

            Label {
                visible: root.devices.length > 0
                text: "Battery:"
                color: root.textColor
                font: Kirigami.Theme.defaultFont
                verticalAlignment: Text.AlignVCenter
            }

            Repeater {
                model: root.devices

                delegate: Label {
                    required property var modelData

                    text: modelData.type + " " + modelData.charge + "%"
                    color: root.textColor
                    font: Kirigami.Theme.defaultFont
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    fullRepresentation: Item {
        implicitWidth: Kirigami.Units.gridUnit * 14
        implicitHeight: fullColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            id: fullColumn
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: root.devices

                delegate: RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Label {
                        text: modelData.type
                        color: root.textColor
                        font: Kirigami.Theme.defaultFont
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        font: Kirigami.Theme.defaultFont
                        elide: Text.ElideRight
                    }

                    Label {
                        text: modelData.charge + "%"
                        font: Kirigami.Theme.defaultFont
                    }
                }
            }

            Label {
                visible: root.devices.length === 0
                text: "No Bluetooth battery levels"
                font: Kirigami.Theme.defaultFont
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    P5Support.DataSource {
        id: batterySource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            root.output = String(data["stdout"] ?? "").replace(/\s+$/, "")
            batterySource.disconnectSource(sourceName)
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
