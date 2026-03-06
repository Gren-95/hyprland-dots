#!/bin/bash
# wifi.sh - Rofi wifi manager

THEME="$HOME/.config/rofi/wifi.rasi"

# Check if wifi is enabled
wifi_state=$(nmcli radio wifi)

if [ "$wifi_state" = "disabled" ]; then
    CHOSEN=$(printf "$(printf '\uf1eb')  Enable Wi-Fi" \
        | rofi -dmenu -p "Wi-Fi" -mesg "Wi-Fi is off" -no-custom -theme "$THEME")
    case "$CHOSEN" in
        *"Enable"*) nmcli radio wifi on ;;
    esac
    exit 0
fi

# Signal strength to icon
signal_icon() {
    local sig=$1
    if   [ "$sig" -ge 75 ]; then printf '\uf1eb'
    elif [ "$sig" -ge 50 ]; then printf '\uf5a4'
    elif [ "$sig" -ge 25 ]; then printf '\uf5a3'
    else                         printf '\uf5a2'
    fi
}

# Build network list
networks=""
while IFS=: read -r ssid signal security inuse; do
    [ -z "$ssid" ] && continue
    icon=$(signal_icon "$signal")
    if [ "$inuse" = "*" ]; then
        networks+="$(printf '\uf00c')  $ssid\n"
    else
        lock=""
        [ -n "$security" ] && lock=" $(printf '\uf023')"
        networks+="$icon  $ssid$lock\n"
    fi
done < <(nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE dev wifi list 2>/dev/null \
    | sort -t: -k4 -r -k2 -rn \
    | awk -F: '!seen[$1]++')

DISCONNECT="$(printf '\uf011')  Disconnect Wi-Fi"
WIFI_OFF="$(printf '\uf204')  Turn Wi-Fi off"

# Build VPN list
vpns=""
while IFS=: read -r name type; do
    active=$(nmcli -t -f NAME con show --active | grep -Fx "$name")
    if [ -n "$active" ]; then
        vpns+="$(printf '\uf49e')  $name\n"
    else
        vpns+="$(printf '\uf023')  $name\n"
    fi
done < <(nmcli -t -f NAME,TYPE con show | grep -E ":vpn$|:wireguard$")

sep=""
[ -n "$vpns" ] && sep="──────────────────────\n$(printf '\uf49e')  VPN Connections\n"

CHOSEN=$(printf "%b" "$networks\n$DISCONNECT\n$WIFI_OFF\n${sep}${vpns}" \
    | grep -v "^$" \
    | rofi -dmenu -p "Network" \
        -mesg "$(printf '\uf00c')   connected | $(printf '\uf023')   secured | $(printf '\uf49e')   vpn on" \
        -no-custom \
        -theme "$THEME")

[ -z "$CHOSEN" ] && exit 0

if echo "$CHOSEN" | grep -q "Turn Wi-Fi off"; then
    nmcli radio wifi off
    exit 0
fi

if echo "$CHOSEN" | grep -q "Disconnect Wi-Fi"; then
    nmcli con down "$(nmcli -t -f NAME,DEVICE con show --active | grep wifi | cut -d: -f1 | head -1)" 2>/dev/null
    exit 0
fi

# Check if chosen item is a VPN entry
vpn_name=$(echo "$CHOSEN" | sed 's/^[^ ]*  //')
if nmcli -t -f NAME,TYPE con show | grep -qE "^${vpn_name}:(vpn|wireguard)$"; then
    active=$(nmcli -t -f NAME con show --active | grep -Fx "$vpn_name")
    if [ -n "$active" ]; then
        nmcli con down "$vpn_name" && notify-send -i network-vpn "VPN" "Disconnected from $vpn_name"
    else
        username=$(rofi -dmenu -p "Username" -mesg "VPN: $vpn_name" -theme "$THEME" < /dev/null)
        [ -z "$username" ] && exit 0
        password=$(rofi -dmenu -p "Password" -mesg "VPN: $vpn_name" -password -theme "$THEME" < /dev/null)
        [ -z "$password" ] && exit 0
        printf "vpn.secrets.username:%s\nvpn.secrets.password:%s\n" "$username" "$password" \
            | nmcli --wait -1 con up "$vpn_name" passwd-file /dev/stdin \
            && notify-send -i network-vpn "VPN" "Connected to $vpn_name"
    fi
    exit 0
fi

# Section header/separator rows — ignore
echo "$CHOSEN" | grep -qE "^──|VPN Connections" && exit 0

# Extract SSID (strip leading icon + spaces + trailing lock icon)
ssid=$(echo "$CHOSEN" | sed 's/^[^ ]*  //; s/ '"$(printf '\uf023')"'$//')

# Check if already saved
saved=$(nmcli -t -f NAME con show | grep -Fx "$ssid")

if [ -n "$saved" ]; then
    nmcli con up "$ssid"
else
    # Prompt for password
    password=$(rofi -dmenu -p "Password" \
        -mesg "Connect to: $ssid" \
        -password \
        -theme "$THEME" \
        < /dev/null)
    [ -z "$password" ] && exit 0
    nmcli dev wifi connect "$ssid" password "$password"
fi
