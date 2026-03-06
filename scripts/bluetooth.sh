#!/bin/bash
# bluetooth.sh - Rofi bluetooth manager

THEME="$HOME/.config/rofi/bluetooth.rasi"

# Check if bluetooth is powered
powered=$(bluetoothctl show | grep -c "Powered: yes")

if [ "$powered" -eq 0 ]; then
    CHOSEN=$(printf "$(printf '\uf294')  Enable Bluetooth" \
        | rofi -dmenu -p "Bluetooth" -mesg "Bluetooth is off" -no-custom -theme "$THEME")
    case "$CHOSEN" in
        *"Enable"*) bluetoothctl power on ;;
    esac
    exit 0
fi

# Build device list
devices=""
while IFS= read -r line; do
    mac=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | cut -d' ' -f3-)
    connected=$(bluetoothctl info "$mac" 2>/dev/null | grep -c "Connected: yes")
    if [ "$connected" -eq 1 ]; then
        devices+="$(printf '\uf294')  $name\n"
    else
        devices+="$(printf '\uf293')  $name\n"
    fi
done < <(bluetoothctl devices)

POWER_OFF="$(printf '\uf011')  Disable Bluetooth"
SCAN="$(printf '\uf002')  Scan for devices"

CHOSEN=$(printf "%b" "$devices\n$SCAN\n$POWER_OFF" \
    | rofi -dmenu -p "Bluetooth" \
        -mesg "● connected  ○ disconnected" \
        -no-custom \
        -theme "$THEME")

[ -z "$CHOSEN" ] && exit 0

if echo "$CHOSEN" | grep -q "Disable"; then
    bluetoothctl power off
    exit 0
fi

if echo "$CHOSEN" | grep -q "Scan"; then
    # Show scanning indicator in background
    echo "$(printf '\uf00d')  Cancel" | rofi -dmenu \
        -p "Bluetooth" \
        -mesg "Scanning for devices (8s)..." \
        -no-custom \
        -theme "$THEME" &
    SCAN_ROFI_PID=$!

    # Scan in background; when done, kill the scanning rofi
    (timeout 8 bluetoothctl scan on 2>/dev/null
     kill $SCAN_ROFI_PID 2>/dev/null) &

    # Wait for rofi to close (either user cancelled or scan finished)
    wait $SCAN_ROFI_PID 2>/dev/null

    bluetoothctl scan off 2>/dev/null
    exec "$0"
    exit 0
fi

# Extract device name and find MAC
device_name=$(echo "$CHOSEN" | sed 's/^[^ ]* \+//')
mac=$(bluetoothctl devices | grep -F "$device_name" | awk '{print $2}')

[ -z "$mac" ] && exit 1

connected=$(bluetoothctl info "$mac" 2>/dev/null | grep -c "Connected: yes")
if [ "$connected" -eq 1 ]; then
    bluetoothctl disconnect "$mac"
else
    bluetoothctl connect "$mac"
fi
