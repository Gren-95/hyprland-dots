#!/bin/bash
# sysinfo.sh — the slow half of the system monitor's data, as one JSON line.
#
# cpu_model, temperatures and fans (hwmon paths are discovered by name, the
# index isn't stable across reboots), disk usage, uptime, and procs[] (top 12
# by instantaneous CPU, from the second iteration of top). Takes about half a
# second, so the UI runs it on its own slower timer; the per-second counters
# come from sysfast.sh.
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

# ───── CPU model ──────────────────────────────────────────────────
cpu_model=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo |
    sed 's/([RT][M]*)//g; s/  */ /g; s/^ //; s/ $//' || true)

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
{"cpu_model":"$cpu_model","cpu_temp":$cpu_temp,"nvme_temp":$nvme_temp,"fan1":$fan1,"fan2":$fan2,"disks":$disks_json,"uptime":"$uptime_str","procs":$procs_json}
EOF
