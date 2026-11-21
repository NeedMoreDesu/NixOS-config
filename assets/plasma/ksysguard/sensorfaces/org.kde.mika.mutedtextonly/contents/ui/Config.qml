/*
    SPDX-FileCopyrightText: 2019 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

import org.kde.kirigami as Kirigami

import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.faces as Faces

Kirigami.FormLayout {
    id: root

    property alias cfg_groupByTotal: groupCheckbox.checked
    property alias cfg_groupSensors: groupSensorsCheckbox.checked
    property alias cfg_showIndicators: showIndicatorsCheckbox.checked

    Controls.CheckBox {
        id: groupCheckbox
        Layout.fillWidth: true
        text: i18nc("@option:check", "Group sensors based on the value of the total sensors.")
    }

    Controls.CheckBox {
        id: groupSensorsCheckbox
        Layout.fillWidth: true
        text: i18nc("@option:check", "Group related sensors into one row (CPU/GPU, memory, network, disk).")
    }

    Controls.CheckBox {
        id: showIndicatorsCheckbox
        Layout.fillWidth: true
        text: i18nc("@option:check", "Show the colored indicator at the start of each row.")
    }
}