#!/usr/bin/env bash
# One tab-separated line per connected Bluetooth device with a known charge:
#   <TYPE-LETTER> <TAB> <PERCENT> <TAB> <DEVICE NAME>
#
# The connected set comes from BlueZ; the charge comes from UPower, which
# merges the kernel HID power_supply (Apple Magic Keyboard, Logitech mouse)
# with BlueZ Battery1 (headsets, LE peripherals). The BlueZ fallback catches
# devices UPower has not picked up yet. Wired devices (e.g. a Magic Keyboard
# on its charging cable) are not in the connected set, so they stay out.
set -u

UPOWER=${UPOWER:-upower}
BLUETOOTHCTL=${BLUETOOTHCTL:-bluetoothctl}

type_letter() {
    case "$1" in
        keyboard) echo K ;;
        mouse) echo M ;;
        touchpad) echo T ;;
        tablet) echo T ;;
        gaming-input) echo G ;;
        headphones | headset) echo H ;;
        speakers) echo S ;;
        phone) echo P ;;
        computer) echo C ;;
        ups) echo U ;;
    esac
}

icon_letter() {
    case "$1" in
        input-keyboard) echo K ;;
        input-mouse) echo M ;;
        input-tablet) echo T ;;
        input-gaming) echo G ;;
        audio-headphones | audio-headset) echo H ;;
        audio-speakers) echo S ;;
        phone) echo P ;;
        computer) echo C ;;
    esac
}

priority() {
    case "$1" in
        K) echo 1 ;;
        M) echo 2 ;;
        H) echo 3 ;;
        S) echo 4 ;;
        *) echo 5 ;;
    esac
}

declare -A bt_macs=()
while read -r _ mac _; do
    [ -n "${mac:-}" ] || continue
    bt_macs[${mac,,}]=1
done < <("$BLUETOOTHCTL" devices Connected 2>/dev/null)

[ ${#bt_macs[@]} -gt 0 ] || exit 0

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT

declare -A seen=()
for source in $("$UPOWER" -e 2>/dev/null); do
    info=$("$UPOWER" -i "$source" 2>/dev/null) || continue

    serial=$(printf '%s\n' "$info" | sed -n 's/^ *serial: *//p' | head -n1)
    native=$(printf '%s\n' "$info" | sed -n 's/^ *native-path: *//p' | head -n1)
    native=${native,,}

    mac=""
    if [ -n "$serial" ] && [ -n "${bt_macs[${serial,,}]:-}" ]; then
        mac=${serial,,}
    else
        for candidate in "${!bt_macs[@]}"; do
            if [[ "$native" == *"$candidate"* || "$native" == *"${candidate//:/-}"* || "$native" == *"${candidate//:/_}"* ]]; then
                mac=$candidate
                break
            fi
        done
    fi
    [ -n "$mac" ] || continue
    [ -z "${seen[$mac]:-}" ] || continue

    percent=$(printf '%s\n' "$info" | sed -n 's/^ *percentage: *\([0-9][0-9]*\)%.*/\1/p' | head -n1)
    [ -n "$percent" ] || continue

    kind=$(printf '%s\n' "$info" | sed -n 's/^  \([a-z][a-z-]*\)$/\1/p' | head -n1)
    letter=$(type_letter "$kind")
    [ -n "$letter" ] || continue

    model=$(printf '%s\n' "$info" | sed -n 's/^ *model: *//p' | head -n1)
    [ -n "$model" ] || model=$mac

    seen[$mac]=1
    printf '%s\t%s\t%s\n' "$letter" "$percent" "$model" >>"$tmp"
done

# UPower can lag behind BlueZ; fill the gaps from the device's Battery1.
for mac in "${!bt_macs[@]}"; do
    [ -z "${seen[$mac]:-}" ] || continue

    info=$("$BLUETOOTHCTL" info "$mac" 2>/dev/null) || continue
    percent=$(printf '%s\n' "$info" | sed -n 's/^ *Battery Percentage:.*(\([0-9][0-9]*\)).*/\1/p' | head -n1)
    [ -n "$percent" ] || continue

    icon=$(printf '%s\n' "$info" | sed -n 's/^ *Icon: *//p' | head -n1)
    letter=$(icon_letter "$icon")
    [ -n "$letter" ] || continue

    name=$(printf '%s\n' "$info" | sed -n 's/^ *Name: *//p' | head -n1)
    [ -n "$name" ] || name=$mac

    printf '%s\t%s\t%s\n' "$letter" "$percent" "$name" >>"$tmp"
done

if [ -s "$tmp" ]; then
    while IFS=$'\t' read -r letter percent name; do
        printf '%s\t%s\t%s\t%s\n' "$(priority "$letter")" "$letter" "$percent" "$name"
    done <"$tmp" | sort -n -k1,1 -k2,2 | cut -f2-
fi
