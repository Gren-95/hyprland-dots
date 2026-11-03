#!/bin/bash
# sysinfo.sh — the slow half of the system monitor's data, as one JSON line.
#
# cpu_model, temperatures and fans (hwmon paths are discovered by name, the
# index isn't stable across reboots), disk usage, uptime, and procs[] (top 12
# by CPU over a 0.3 s window, from two reads of /proc/*/stat). Takes about
# a third of a second, so the UI runs it on its own slower timer; the
# per-second counters come from sysfast.sh. Reads files with bash builtins
# where it can: every spawn counts, because this runs every couple of seconds.
set -euo pipefail
# uptime and df print localised words and decimals; the JSON needs C.
export LC_ALL=C
shopt -s extglob nullglob

# Process CPU needs two samples a moment apart. The second one is taken in the
# background so the other probes run during the wait. Each sample line is
# "pid ticks rss_pages comm".
PROC_WINDOW=0.3
PROC_CLK_TCK=100 # USER_HZ, fixed at 100 for /proc on Linux
PROC_PAGE_KB=4
samples_dir=$(mktemp -d)
trap 'rm -rf "$samples_dir"' EXIT

# Normally the comm is the single word in field 2. A comm with spaces breaks
# that split, so those lines (rare) take the slow path, cutting the comm out
# between the first "(" and the last ")".
sample_procs() {
    awk '{
        if ($2 ~ /\)$/) {
            print $1 "\t" $14 + $15 "\t" $24 "\t" substr($2, 2, length($2) - 2)
            next
        }
        lp = index($0, "(")
        rp = length($0)
        while (substr($0, rp, 1) != ")") rp--
        split(substr($0, rp + 2), f, " ")
        print substr($0, 1, lp - 2) "\t" f[12] + f[13] "\t" f[22] "\t" substr($0, lp + 1, rp - lp - 1)
    }' /proc/[0-9]*/stat 2>/dev/null
}

sample_procs >"$samples_dir/first"
first_at=$EPOCHREALTIME
{
    sleep "$PROC_WINDOW"
    sample_procs >"$samples_dir/second"
    echo "$EPOCHREALTIME" >"$samples_dir/second_at"
} &
procs_pid=$!

# ───── Temps & fans (hwmon, discovered by name) ──────────────────
declare -A hwmon_dir
for dir in /sys/class/hwmon/hwmon*; do
    read -r hwmon_name <"$dir/name" 2>/dev/null || continue
    # First of each name wins, as the old per-name search did.
    [[ -n "${hwmon_dir[$hwmon_name]:-}" ]] || hwmon_dir[$hwmon_name]=$dir
done

# Value of a sysfs file, or 0 when it is missing or unreadable.
read_first() {
    local value=0
    [[ -r "$1" ]] && read -r value <"$1" 2>/dev/null || true
    echo "${value:-0}"
}
# Millidegrees to whole degrees, rounded.
temp_c() { echo $((($(read_first "$1") + 500) / 1000)); }

coretemp_h=${hwmon_dir[coretemp]:-}
nvme_h=${hwmon_dir[nvme]:-}
fans_h=${hwmon_dir[dell_smm]:-${hwmon_dir[dell_ddv]:-}}

cpu_temp=$(temp_c "${coretemp_h:-}/temp1_input")
nvme_temp=$(temp_c "${nvme_h:-}/temp1_input")
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
        BEGIN { printf "[" }
        NR == 1 || $2 ~ /^\/boot/ || seen[$1]++ { next }
        {
            pct = $5; gsub(/%/, "", pct)
            printf "%s{\"mount\":\"%s\",\"used_gb\":%.1f,\"total_gb\":%.1f,\"pct\":%s}", n++ ? "," : "", $2, $4/1048576, $3/1048576, pct
        }
        END { printf "]" }
    '
) || true
[[ -n "$disks_json" ]] || disks_json="[]"

# ───── Uptime ─────────────────────────────────────────────────────
uptime_str=$(uptime -p)
uptime_str=${uptime_str#up }

# ───── CPU model ──────────────────────────────────────────────────
cpu_model=""
while IFS= read -r line; do
    if [[ "$line" == "model name"* ]]; then
        cpu_model=${line#*: }
        break
    fi
done </proc/cpuinfo
cpu_model=${cpu_model//"(R)"/}
cpu_model=${cpu_model//"(TM)"/}
cpu_model=${cpu_model//+( )/ }
cpu_model=${cpu_model# }
cpu_model=${cpu_model% }

# ───── Top processes (CPU over the sample window) ────────────────
wait "$procs_pid" || true
second_at=$(<"$samples_dir/second_at")
read -r _ mem_total_kb _ </proc/meminfo
window_us=$((${second_at/./} - ${first_at/./}))
procs_json=$(awk -F'\t' -v window_us="$window_us" \
    -v clk="$PROC_CLK_TCK" -v page_kb="$PROC_PAGE_KB" -v mem_kb="$mem_total_kb" '
    NR == FNR { before[$1] = $2; next }
    ($1 in before) {
        n++
        pid[n] = $1; name[n] = $4
        cpu[n] = ($2 - before[$1]) / (window_us / 1000000 * clk) * 100
        mem[n] = mem_kb > 0 ? $3 * page_kb / mem_kb * 100 : 0
    }
    END {
        printf "["
        for (k = 0; k < 12 && k < n; k++) {
            best = 0
            for (i = 1; i <= n; i++)
                if (!(i in taken) && (best == 0 || cpu[i] > cpu[best])) best = i
            taken[best] = 1
            nm = name[best]
            gsub(/\\/, "\\\\", nm); gsub(/"/, "\\\"", nm)
            printf "%s{\"pid\":%s,\"name\":\"%s\",\"cpu\":%.1f,\"mem\":%.1f}", k ? "," : "", pid[best], nm, cpu[best], mem[best]
        }
        printf "]"
    }' "$samples_dir/first" "$samples_dir/second" || echo "[]")
[[ -n "$procs_json" ]] || procs_json="[]"

# ───── Emit ───────────────────────────────────────────────────────
cat <<EOF
{"cpu_model":"$cpu_model","cpu_temp":$cpu_temp,"nvme_temp":$nvme_temp,"fan1":$fan1,"fan2":$fan2,"disks":$disks_json,"uptime":"$uptime_str","procs":$procs_json}
EOF
