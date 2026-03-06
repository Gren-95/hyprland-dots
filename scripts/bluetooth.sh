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

# Build device list from all known devices
devices=""
while IFS= read -r line; do
    mac=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | cut -d' ' -f3-)

    info=$(bluetoothctl info "$mac" 2>/dev/null)
    paired=$(echo "$info" | grep -c "Paired: yes")
    connected=$(echo "$info" | grep -c "Connected: yes")

    # Skip unpaired devices with no real name (anonymous beacons)
    if [ "$paired" -eq 0 ]; then
        [[ "$name" =~ ^[0-9A-Fa-f]{2}[-:] ]] && continue
    fi

    if [ "$connected" -eq 1 ]; then
        devices+="$(printf '\uf294')  $name\n"
    elif [ "$paired" -eq 1 ]; then
        devices+="$(printf '\uf293')  $name\n"
    else
        devices+="$(printf '\uf0c1')  $name [pair]\n"
    fi
done < <(bluetoothctl devices 2>/dev/null)

POWER_OFF="$(printf '\uf011')  Disable Bluetooth"
SCAN="$(printf '\uf002')  Scan for devices"

mesg="$(printf '\uf294') connected  $(printf '\uf293') paired  $(printf '\uf0c1') unpaired"
CHOSEN=$(printf "%b" "$devices\n$SCAN\n$POWER_OFF" \
    | rofi -dmenu -p "Bluetooth" \
        -mesg "$mesg" \
        -no-custom \
        -theme "$THEME")

[ -z "$CHOSEN" ] && exit 0

if echo "$CHOSEN" | grep -q "Disable"; then
    bluetoothctl power off
    exit 0
fi

if echo "$CHOSEN" | grep -q "Scan"; then
    echo "$(printf '\uf00d')  Cancel" | rofi -dmenu \
        -p "Bluetooth" \
        -mesg "Scanning for devices (8s)..." \
        -no-custom \
        -theme "$THEME" &
    SCAN_ROFI_PID=$!

    (bluetoothctl --timeout 8 scan on 2>/dev/null
     kill $SCAN_ROFI_PID 2>/dev/null) &

    wait $SCAN_ROFI_PID 2>/dev/null
    exec "$0"
    exit 0
fi

# Extract device name and find MAC
device_name=$(echo "$CHOSEN" | sed 's/^[^ ]*  //; s/ \[pair\]$//')
mac=$(bluetoothctl devices 2>/dev/null | grep -F "$device_name" | awk '{print $2}' | head -1)

[ -z "$mac" ] && exit 1

if echo "$CHOSEN" | grep -q "\[pair\]"; then
    bluetoothctl pair "$mac" && bluetoothctl connect "$mac"
else
    connected=$(bluetoothctl info "$mac" 2>/dev/null | grep -c "Connected: yes")
    if [ "$connected" -eq 1 ]; then
        bluetoothctl disconnect "$mac"
    else
        bluetoothctl connect "$mac"
    fi
fi
