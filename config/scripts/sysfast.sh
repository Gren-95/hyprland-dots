#!/bin/bash
# sysfast.sh — the cheap half of the system monitor's data, as one JSON line.
#
# Only /proc and /sys reads, no sleeps, so it can run twice a second. CPU time
# is reported as cumulative counters (per core and total: [total, idle]) and
# the UI turns the difference between two samples into percentages. Network
# and disk counters are cumulative bytes with a millisecond timestamp, as is
# the iGPU idle (RC6) residency, for the
# same reason. Slower probes (processes, disk usage, temperatures) live in
# sysinfo.sh.
set -euo pipefail
export LC_ALL=C
shopt -s nullglob

# One awk pass over every /proc and /sys counter file: CPU counters, mean CPU
# frequency, memory, default-route interface and disk bytes. (Separate awk and
# cat spawns cost more than the reading itself, and this runs twice a second.)
IFS=$'\t' read -r cpu_json cpu_freq mem_json net_iface io_read io_write < <(awk '
    FILENAME == "/proc/stat" && /^cpu[0-9]* / {
        total = 0
        for (i = 2; i <= 8; i++) total += $i
        idle = $5 + $6
        if ($1 == "cpu") all = "[" total "," idle "]"
        else cores = cores (cores == "" ? "" : ",") "[" total "," idle "]"
        next
    }
    FILENAME ~ /scaling_cur_freq$/ { freq_sum += $1; freq_n++; next }
    FILENAME == "/proc/meminfo" {
        if ($1 == "MemTotal:")          total_kb = $2
        else if ($1 == "MemFree:")      free = $2
        else if ($1 == "MemAvailable:") avail = $2
        else if ($1 == "Buffers:")      buffers = $2
        else if ($1 == "Cached:")       cached += $2
        else if ($1 == "SReclaimable:") cached += $2
        else if ($1 == "SwapTotal:")    swap_total = $2
        else if ($1 == "SwapFree:")     swap_free = $2
        next
    }
    FILENAME == "/proc/net/route" { if (FNR > 1 && $2 == "00000000" && iface == "") iface = $1; next }
    FILENAME == "/proc/diskstats" && $3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+)$/ { r += $6; w += $10 }
    END {
        g = 1048576
        printf "{\"all\":%s,\"cores\":[%s]}\t", all, cores
        printf "%d\t", freq_n ? freq_sum / freq_n / 1000 : 0
        printf "{\"total\":%.2f,\"used\":%.2f,\"available\":%.2f,\"cached\":%.2f,\"buffers\":%.2f,\"free\":%.2f,\"swap_total\":%.2f,\"swap_used\":%.2f}\t",
            total_kb / g, (total_kb - avail) / g, avail / g, cached / g, buffers / g, free / g,
            swap_total / g, (swap_total - swap_free) / g
        printf "%s\t%.0f\t%.0f\n", iface == "" ? "-" : iface, r * 512, w * 512
    }' /proc/stat /proc/meminfo /proc/net/route /proc/diskstats \
    /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq)
[[ "$net_iface" == "-" ]] && net_iface=""

read -r load1 load5 load15 _ </proc/loadavg

net_rx=0
net_tx=0
if [[ -n "$net_iface" && -d "/sys/class/net/$net_iface/statistics" ]]; then
    net_rx=$(<"/sys/class/net/$net_iface/statistics/rx_bytes")
    net_tx=$(<"/sys/class/net/$net_iface/statistics/tx_bytes")
fi

# Intel iGPU (i915): current (requested) and maximum clock; the actual clock reads 0 in RC6, plus cumulative RC6 (idle)
# residency, from which the UI derives how busy the engine was.
gpu_dir=""
for card in /sys/class/drm/card*; do
    if [[ -r "$card/gt_act_freq_mhz" ]]; then
        gpu_dir=$card
        break
    fi
done
gpu_act=0
gpu_max=0
gpu_rc6=0
if [[ -n "$gpu_dir" ]]; then
    [[ -r "$gpu_dir/gt_cur_freq_mhz" ]] && gpu_act=$(<"$gpu_dir/gt_cur_freq_mhz")
    [[ -r "$gpu_dir/gt_RP0_freq_mhz" ]] && gpu_max=$(<"$gpu_dir/gt_RP0_freq_mhz")
    [[ -r "$gpu_dir/gt/gt0/rc6_residency_ms" ]] && gpu_rc6=$(<"$gpu_dir/gt/gt0/rc6_residency_ms")
fi

# Milliseconds since the epoch, from bash's own clock (no date(1) spawn).
ts_us=${EPOCHREALTIME/./}
ts_ms=$((ts_us / 1000))

cat <<JSON
{"cpu":$cpu_json,"load":[$load1,$load5,$load15],"cpu_freq_mhz":$cpu_freq,"mem":$mem_json,"net":{"iface":"$net_iface","rx":$net_rx,"tx":$net_tx},"io":{"read":$io_read,"write":$io_write},"gpu":{"act":$gpu_act,"max":$gpu_max,"rc6_ms":$gpu_rc6},"ts_ms":$ts_ms}
JSON
