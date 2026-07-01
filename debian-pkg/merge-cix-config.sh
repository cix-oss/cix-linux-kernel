#!/usr/bin/env bash
# Merge CIX defconfig into Debian arm64 config.
#
# For each CONFIG_ option in the CIX defconfig:
#   - If Debian config has it, replace the value with CIX's value
#   - If Debian config doesn't have it, append it
# Debian-only options are left unchanged.
#
# Usage: ./merge-cix-config.sh <cix-defconfig> <debian-arm64-config>
# Output goes to stdout; redirect to a file to save.
set -euo pipefail

CIX_CONFIG="${1:?Usage: $0 <cix-defconfig> <debian-arm64-config>}"
DEBIAN_CONFIG="${2:?}"

# Read CIX config options into an associative array
declare -A cix_opts
while IFS= read -r line; do
    # Skip "not set" entries and non-CONFIG lines
    [[ "$line" == "# CONFIG_"* ]] && continue
    [[ "$line" != "CONFIG_"* ]] && continue
    name="${line%%=*}"
    value="${line#*=}"
    cix_opts["$name"]="$value"
done < "$CIX_CONFIG"

# Process Debian config line by line
declare -A seen
while IFS= read -r line; do
    if [[ "$line" == "# CONFIG_"*" is not set" ]]; then
        # Extract config name: "# CONFIG_FOO is not set" -> CONFIG_FOO
        name="${line#\# }"
        name="${name% is not set}"
        if [[ -n "${cix_opts[$name]:-}" ]]; then
            echo "${name}=${cix_opts[$name]}"
        else
            echo "$line"
        fi
        seen["$name"]=1
    elif [[ "$line" == "CONFIG_"*"="* ]]; then
        name="${line%%=*}"
        if [[ -n "${cix_opts[$name]:-}" ]]; then
            echo "${name}=${cix_opts[$name]}"
        else
            echo "$line"
        fi
        seen["$name"]=1
    else
        echo "$line"
    fi
done < "$DEBIAN_CONFIG"

# Append CIX options that Debian config doesn't have
echo ""
echo "## CIX-specific options (not in Debian default config)"
for name in "${!cix_opts[@]}"; do
    if [[ -z "${seen[$name]:-}" ]]; then
        echo "${name}=${cix_opts[$name]}"
    fi
done
