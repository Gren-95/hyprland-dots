#!/bin/bash
# sysinfo.sh — emit system metrics as JSON for SystemMonitor.qml.
#
# Output: single JSON line with cpu_pct, cpu_cores[], cpu_temp,
# ram_used_gb, ram_total_gb, ram_pct, nvme_temp, fan1, fan2, disks[],
# uptime, plus load[], cpu_model, cpu_freq_mhz, mem{} breakdown, net{} and
# io{} cumulative byte counters with ts_ms (the UI turns them into rates),
# and procs[] (top 12 by instantaneous CPU).
#
# CPU usage samples /proc/stat twice with a 200ms gap. hwmon paths
# are discovered by name (index isn't stable across reboots).
set -euo pipefail
# top and uptime print localised decimals and words; the JSON needs C.
export LC_ALL=C

# ───── helpers ────────────────────────────────────────────────────
find_hwmon() {
    for h in /sys/class/hwmon/hwmon*; do
        [[ "$(cat "$h/name" 2>/dev/null)" == "$1" ]] && {
            echo "$h"
            return 0
        }
    done
    return 1
}

read_first() {
    [[ -r "$1" ]] && cat "$1" 2>/dev/null || echo 0
}

# Sample /proc/stat: returns "total idle" for cpu line, and per-core lines.
sample_cpu() { awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5; exit }' /proc/stat; }
sample_cpu_cores() { awk '/^cpu[0-9]+/ { print $1, $2+$3+$4+$5+$6+$7+$8, $5 }' /proc/stat; }

# The process sample takes about half a second, so start it now and collect
# it after the other probes instead of adding to the total time.
top_out=$(mktemp)
trap 'rm -f "$top_out"' EXIT
top -b -n2 -d0.3 -w 200 -o %CPU >"$top_out" 2>/dev/null &
top_pid=$!

# ───── CPU usage ──────────────────────────────────────────────────
read -r t1 i1 < <(sample_cpu)
declare -A tot1 idl1
while read -r cpu tot idl; do
    tot1[$cpu]=$tot
    idl1[$cpu]=$idl
done < <(sample_cpu_cores)

sleep 0.2

read -r t2 i2 < <(sample_cpu)
declare -A tot2 idl2
while read -r cpu tot idl; do
    tot2[$cpu]=$tot
    idl2[$cpu]=$idl
done < <(sample_cpu_cores)

cpu_pct=$(awk -v t1="$t1" -v t2="$t2" -v i1="$i1" -v i2="$i2" \
    'BEGIN { td=t2-t1; id=i2-i1; printf "%.1f", (td > 0) ? (1 - id/td) * 100 : 0 }')

cores_json="["
first=1
for cpu in $(printf '%s\n' "${!tot1[@]}" | sort -V); do
    td=$((tot2[$cpu] - tot1[$cpu]))
    id=$((idl2[$cpu] - idl1[$cpu]))
    pct=$(awk -v t="$td" -v i="$id" 'BEGIN { printf "%.1f", (t > 0) ? (1 - i/t) * 100 : 0 }')
    [[ $first -eq 0 ]] && cores_json+=","
    cores_json+="$pct"
    first=0
done
cores_json+="]"

# ───── RAM ────────────────────────────────────────────────────────
ram_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
ram_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
ram_used_kb=$((ram_total_kb - ram_avail_kb))
ram_used_gb=$(awk -v k="$ram_used_kb" 'BEGIN { printf "%.1f", k/1048576 }')
ram_total_gb=$(awk -v k="$ram_total_kb" 'BEGIN { printf "%.1f", k/1048576 }')
ram_pct=$(awk -v u="$ram_used_kb" -v t="$ram_total_kb" \
    'BEGIN { printf "%.1f", (t > 0) ? u/t*100 : 0 }')

# ───── Temps & fans (hwmon, discovered by name) ──────────────────
coretemp_h=$(find_hwmon coretemp || true)
nvme_h=$(find_hwmon nvme || true)
fans_h=$(find_hwmon dell_smm || find_hwmon dell_ddv || true)

cpu_temp=$(awk -v t="$(read_first "${coretemp_h:-}/temp1_input")" \
    'BEGIN { printf "%.0f", t/1000 }')
nvme_temp=$(awk -v t="$(read_first "${nvme_h:-}/temp1_input")" \
    'BEGIN { printf "%.0f", t/1000 }')
fan1=$(read_first "${fans_h:-}/fan1_input")
fan2=$(read_first "${fans_h:-}/fan2_input")

# ───── Disks ──────────────────────────────────────────────────────
# All real local filesystems. Skip pseudo-fs (tmpfs/devtmpfs/efivarfs),
# firmware partitions (/boot, /boot/efi), and dedupe by source device so
# a partition mounted at both / and /home doesn't appear twice.
disks_json=$(
    df -l --output=source,target,size,used,pcent \
        -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x fuse 2>/dev/null |
        awk '
        NR == 1 { next }
        $2 ~ /^\/boot/ { next }
        seen[$1]++   { next }
        {
            pct = $5; gsub(/%/, "", pct)
            printf "%s\t%.1f\t%.1f\t%s\n", $2, $4/1048576, $3/1048576, pct
        }
    ' | awk -F'\t' '
        BEGIN { first = 1; printf "[" }
        {
            if (!first) printf ","
            printf "{\"mount\":\"%s\",\"used_gb\":%s,\"total_gb\":%s,\"pct\":%s}", $1, $2, $3, $4
            first = 0
        }
        END { printf "]" }
    '
) || true

# ───── Uptime ─────────────────────────────────────────────────────
uptime_str=$(uptime -p | sed 's/^up //')

# ───── Load, frequency, model ────────────────────────────────────
read -r load1 load5 load15 _ </proc/loadavg
cpu_model=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo |
    sed 's/([RT][M]*)//g; s/  */ /g; s/^ //; s/ $//' || true)
cpu_freq=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null |
    awk '{ s += $1; n++ } END { printf "%d", n ? s / n / 1000 : 0 }' || true)
cpu_freq=${cpu_freq:-0}

# ───── Memory breakdown (GB) ──────────────────────────────────────
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

# ───── Network and disk I/O counters (cumulative; the UI takes rates) ─
net_iface=$(ip route show default 2>/dev/null |
    awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }' || true)
net_rx=0
net_tx=0
if [[ -n "$net_iface" && -d "/sys/class/net/$net_iface/statistics" ]]; then
    net_rx=$(read_first "/sys/class/net/$net_iface/statistics/rx_bytes")
    net_tx=$(read_first "/sys/class/net/$net_iface/statistics/tx_bytes")
fi
read -r io_read io_write < <(awk '
    $3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+)$/ { r += $6; w += $10 }
    END { printf "%.0f %.0f\n", r * 512, w * 512 }' /proc/diskstats)
ts_ms=$(date +%s%3N)

# ───── Top processes (instantaneous CPU: second top iteration) ────
wait "$top_pid" || true
procs_json=$(awk '
    /^top -/ { block++ }
    block == 2 && $1 == "PID" { reading = 1; count = 0; first = 1; printf "["; next }
    block == 2 && reading && count < 12 && NF >= 12 {
        name = $12
        for (i = 13; i <= NF; i++) name = name " " $i
        if (name == "top") next
        gsub(/\\/, "\\\\", name); gsub(/"/, "\\\"", name)
        if (!first) printf ","
        printf "{\"pid\":%s,\"name\":\"%s\",\"user\":\"%s\",\"cpu\":%s,\"mem\":%s}", $1, name, $2, $9, $10
        first = 0
        count++
    }
    END { if (reading) printf "]"; else printf "[]" }' "$top_out" || echo "[]")
[[ -n "$procs_json" ]] || procs_json="[]"

# ───── Emit ───────────────────────────────────────────────────────
cat <<EOF
{"cpu_pct":$cpu_pct,"cpu_cores":$cores_json,"cpu_temp":$cpu_temp,"ram_used_gb":$ram_used_gb,"ram_total_gb":$ram_total_gb,"ram_pct":$ram_pct,"nvme_temp":$nvme_temp,"fan1":$fan1,"fan2":$fan2,"disks":$disks_json,"uptime":"$uptime_str","load":[$load1,$load5,$load15],"cpu_model":"$cpu_model","cpu_freq_mhz":$cpu_freq,"mem":$mem_json,"net":{"iface":"$net_iface","rx":$net_rx,"tx":$net_tx},"io":{"read":$io_read,"write":$io_write},"ts_ms":$ts_ms,"procs":$procs_json}
EOF
