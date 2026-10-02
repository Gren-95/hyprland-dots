#!/bin/bash
# sysfast.sh — the cheap half of the system monitor's data, as one JSON line.
#
# Only /proc and /sys reads, no sleeps, so it can run twice a second. CPU time
# is reported as cumulative counters (per core and total: [total, idle]) and
# the UI turns the difference between two samples into percentages. Network
# and disk counters are cumulative bytes with a millisecond timestamp, for the
# same reason. Slower probes (processes, disk usage, temperatures) live in
# sysinfo.sh.
set -euo pipefail
export LC_ALL=C

cpu_json=$(awk '
    /^cpu[0-9]* / || /^cpu[0-9]+ / {
        total = 0
        for (i = 2; i <= 8; i++) total += $i
        idle = $5 + $6
        if ($1 == "cpu") all = "[" total "," idle "]"
        else cores = cores (cores == "" ? "" : ",") "[" total "," idle "]"
    }
    END { printf "{\"all\":%s,\"cores\":[%s]}", all, cores }' /proc/stat)

read -r load1 load5 load15 _ </proc/loadavg

cpu_freq=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null |
    awk '{ s += $1; n++ } END { printf "%d", n ? s / n / 1000 : 0 }' || true)
cpu_freq=${cpu_freq:-0}

mem_json=$(awk '
    /^MemTotal:/     { total = $2 }
    /^MemFree:/      { free = $2 }
    /^MemAvailable:/ { avail = $2 }
    /^Buffers:/      { buffers = $2 }
    /^Cached:/       { cached = $2 }
    /^SReclaimable:/ { cached += $2 }
    /^SwapTotal:/    { swap_total = $2 }
    /^SwapFree:/     { swap_free = $2 }
    END {
        g = 1048576
        printf "{\"total\":%.2f,\"used\":%.2f,\"available\":%.2f,\"cached\":%.2f,\"buffers\":%.2f,\"free\":%.2f,\"swap_total\":%.2f,\"swap_used\":%.2f}",
            total / g, (total - avail) / g, avail / g, cached / g, buffers / g, free / g,
            swap_total / g, (swap_total - swap_free) / g
    }' /proc/meminfo)

# Interface of the default route, from the kernel table (no ip(8) spawn).
net_iface=$(awk 'NR > 1 && $2 == "00000000" { print $1; exit }' /proc/net/route || true)
net_rx=0
net_tx=0
if [[ -n "$net_iface" && -d "/sys/class/net/$net_iface/statistics" ]]; then
    net_rx=$(<"/sys/class/net/$net_iface/statistics/rx_bytes")
    net_tx=$(<"/sys/class/net/$net_iface/statistics/tx_bytes")
fi

read -r io_read io_write < <(awk '
    $3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+)$/ { r += $6; w += $10 }
    END { printf "%.0f %.0f\n", r * 512, w * 512 }' /proc/diskstats)

ts_ms=$(date +%s%3N)

cat <<JSON
{"cpu":$cpu_json,"load":[$load1,$load5,$load15],"cpu_freq_mhz":$cpu_freq,"mem":$mem_json,"net":{"iface":"$net_iface","rx":$net_rx,"tx":$net_tx},"io":{"read":$io_read,"write":$io_write},"ts_ms":$ts_ms}
JSON
