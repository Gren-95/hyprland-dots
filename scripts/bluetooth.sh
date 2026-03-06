#!/bin/bash
# bluetooth.sh - Rofi bluetooth manager

THEME="$HOME/.config/rofi/bluetooth.rasi"
DISCOVERED_CACHE="${XDG_RUNTIME_DIR:-/tmp}/bt-discovered.txt"

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

# Get paired MACs once (used to filter discovered cache)
paired_macs=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}')

# Build device list from paired devices
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
done < <(bluetoothctl devices Paired 2>/dev/null)

# Add discovered (unpaired) devices from cache
discovered_devices=""
if [ -f "$DISCOVERED_CACHE" ]; then
    while read -r mac name; do
        # Skip if name looks like a MAC (anonymous beacon)
        [[ "$name" =~ ^[0-9A-Fa-f]{2}[-:] ]] && continue
        # Skip if already paired
        echo "$paired_macs" | grep -qF "$mac" && continue
        discovered_devices+="$(printf '\uf0c1')  $name [pair]\n"
    done < "$DISCOVERED_CACHE"
fi

POWER_OFF="$(printf '\uf011')  Disable Bluetooth"
SCAN="$(printf '\uf002')  Scan for devices"

mesg="$(printf '\uf294') connected  $(printf '\uf293') paired  $(printf '\uf0c1') unpaired"
CHOSEN=$(printf "%b" "$devices$discovered_devices\n$SCAN\n$POWER_OFF" \
    | rofi -dmenu -p "Bluetooth" \
        -mesg "$mesg" \
        -no-custom \
        -theme "$THEME")

[ -z "$CHOSEN" ] && exit 0

if echo "$CHOSEN" | grep -q "Disable"; then
    bluetoothctl power off
    rm -f "$DISCOVERED_CACHE"
    exit 0
fi

if echo "$CHOSEN" | grep -q "Scan"; then
    # Show scanning rofi in background
    echo "$(printf '\uf00d')  Cancel" | rofi -dmenu \
        -p "Bluetooth" \
        -mesg "Scanning for devices (8s)..." \
        -no-custom \
        -theme "$THEME" &
    SCAN_ROFI_PID=$!

    # Scan, capture devices and their names
    (tmpout=$(mktemp)
     bluetoothctl --timeout 8 scan on 2>&1 \
         | sed 's/\x1B\[[0-9;]*m//g' > "$tmpout"

     # Add newly discovered devices
     grep -E "^\[NEW\] Device [0-9A-F:]" "$tmpout" \
         | sed 's/^\[NEW\] Device //' >> "$DISCOVERED_CACHE"

     # Update with real names from [CHG] Name events
     grep -E "^\[CHG\] Device [0-9A-F:].* Name: " "$tmpout" \
         | while IFS= read -r chgline; do
             cmac=$(echo "$chgline" | awk '{print $3}')
             cname=$(echo "$chgline" | sed 's/.*Name: //')
             sed -i "s|^$cmac .*|$cmac $cname|" "$DISCOVERED_CACHE"
         done

     sort -u "$DISCOVERED_CACHE" -o "$DISCOVERED_CACHE" 2>/dev/null
     rm -f "$tmpout"
     kill $SCAN_ROFI_PID 2>/dev/null) &

    wait $SCAN_ROFI_PID 2>/dev/null
    exec "$0"
    exit 0
fi

# Extract device name
device_name=$(echo "$CHOSEN" | sed 's/^[^ ]*  //; s/ \[pair\]$//')

# Find MAC from paired list or discovered cache
mac=$(bluetoothctl devices Paired 2>/dev/null | grep -F "$device_name" | awk '{print $2}')
if [ -z "$mac" ] && [ -f "$DISCOVERED_CACHE" ]; then
    mac=$(grep -F "$device_name" "$DISCOVERED_CACHE" | awk '{print $1}' | head -1)
fi

[ -z "$mac" ] && exit 1

if echo "$CHOSEN" | grep -q "\[pair\]"; then
    bluetoothctl pair "$mac" && bluetoothctl connect "$mac"
    sed -i "/$mac/d" "$DISCOVERED_CACHE" 2>/dev/null
else
    connected=$(bluetoothctl info "$mac" 2>/dev/null | grep -c "Connected: yes")
    if [ "$connected" -eq 1 ]; then
        bluetoothctl disconnect "$mac"
    else
        bluetoothctl connect "$mac"
    fi
fi
