#!/bin/bash
# sysinfo.sh — emit system metrics as JSON for SystemMonitor.qml.
#
# Output: single JSON line with cpu_pct, cpu_cores[], cpu_temp,
# ram_used_gb, ram_total_gb, ram_pct, nvme_temp, fan1, fan2,
# disk_pct, uptime.
#
# CPU usage samples /proc/stat twice with a 200ms gap. hwmon paths
# are discovered by name (index isn't stable across reboots).
set -uo pipefail

# ───── helpers ────────────────────────────────────────────────────
find_hwmon() {
    for h in /sys/class/hwmon/hwmon*; do
        [[ "$(cat "$h/name" 2>/dev/null)" == "$1" ]] && { echo "$h"; return 0; }
    done
    return 1
}

read_first() {
    [[ -r "$1" ]] && cat "$1" 2>/dev/null || echo 0
}

# Sample /proc/stat: returns "total idle" for cpu line, and per-core lines.
sample_cpu()       { awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5; exit }' /proc/stat; }
sample_cpu_cores() { awk '/^cpu[0-9]+/ { print $1, $2+$3+$4+$5+$6+$7+$8, $5 }' /proc/stat; }

# ───── CPU usage ──────────────────────────────────────────────────
read t1 i1 < <(sample_cpu)
declare -A tot1 idl1
while read -r cpu tot idl; do
    tot1[$cpu]=$tot
    idl1[$cpu]=$idl
done < <(sample_cpu_cores)

sleep 0.2

read t2 i2 < <(sample_cpu)
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
    td=$(( tot2[$cpu] - tot1[$cpu] ))
    id=$(( idl2[$cpu] - idl1[$cpu] ))
    pct=$(awk -v t="$td" -v i="$id" 'BEGIN { printf "%.1f", (t > 0) ? (1 - i/t) * 100 : 0 }')
    [[ $first -eq 0 ]] && cores_json+=","
    cores_json+="$pct"
    first=0
done
cores_json+="]"

# ───── RAM ────────────────────────────────────────────────────────
ram_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
ram_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
ram_used_kb=$(( ram_total_kb - ram_avail_kb ))
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
       -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x fuse 2>/dev/null \
    | awk '
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
)

# ───── Uptime ─────────────────────────────────────────────────────
uptime_str=$(uptime -p | sed 's/^up //')

# ───── Emit ───────────────────────────────────────────────────────
cat <<EOF
{"cpu_pct":$cpu_pct,"cpu_cores":$cores_json,"cpu_temp":$cpu_temp,"ram_used_gb":$ram_used_gb,"ram_total_gb":$ram_total_gb,"ram_pct":$ram_pct,"nvme_temp":$nvme_temp,"fan1":$fan1,"fan2":$fan2,"disks":$disks_json,"uptime":"$uptime_str"}
EOF
