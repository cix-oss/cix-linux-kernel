#!/usr/bin/env bash
# Check if config.cix options actually made it into the final kernel config.
# Usage: ./check-config.sh <config.cix> <kernel-config>
#
# Reports options that were set in config.cix but got changed or dropped
# by olddefconfig (usually due to unmet dependencies).
set -euo pipefail

CIX_CONFIG="${1:?Usage: $0 <config.cix> <kernel-config>}"
KERNEL_CONFIG="${2:?}"

missing=0
downgraded=0
matched=0

while IFS= read -r line; do
    [[ "$line" =~ ^CONFIG_ ]] || continue

    name="${line%%=*}"
    cix_value="${line#*=}"

    # Skip comments and not-set entries
    [[ "$name" == "#"* ]] && continue
    [[ "$cix_value" == "n" ]] && continue

    # Find in kernel config
    kernel_line=$(grep -E "^${name}=|^# ${name} is not set" "$KERNEL_CONFIG" 2>/dev/null || true)

    if [[ -z "$kernel_line" ]]; then
        echo "MISSING  ${name}  cix=${cix_value}  kernel=(absent)"
        missing=$((missing + 1))
    elif [[ "$kernel_line" == "# ${name} is not set" ]]; then
        echo "DROPPED  ${name}  cix=${cix_value}  kernel=n (dependency not met?)"
        downgraded=$((downgraded + 1))
    else
        kernel_value="${kernel_line#*=}"
        if [[ "$cix_value" != "$kernel_value" ]]; then
            echo "CHANGED  ${name}  cix=${cix_value}  kernel=${kernel_value}"
            downgraded=$((downgraded + 1))
        else
            matched=$((matched + 1))
        fi
    fi
done < "$CIX_CONFIG"

echo ""
echo "=== Summary ==="
echo "Matched:   ${matched}"
echo "Changed/Dropped: ${downgraded}"
echo "Missing:   ${missing}"
