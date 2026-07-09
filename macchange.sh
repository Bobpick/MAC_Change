#!/bin/bash
#
# macchange.sh
# Hourly MAC Address Randomizer with Jitter and Timestamps
#
# Privacy tool for Linux - randomizes MAC addresses on specified interfaces
# with a random delay (jitter) to avoid predictable patterns.
#
# Run as root (via cron or systemd timer)
#
# Features:
#   - Random jitter (1-59 minutes)
#   - Full execution timestamps in logs
#   - Automatic Wi-Fi reconnect via nmcli
#   - Safe logging
#

set -euo pipefail

# ====================== CONFIGURATION ======================
LOG_FILE="/var/log/macchange.log"
INTERFACES=("eno1" "wlp4s0")      # Add/remove interfaces as needed
WIFI_INTERFACE="wlp4s0"           # Wi-Fi interface for nmcli reconnect
MIN_JITTER=60                     # Minimum jitter in seconds (1 minute)
MAX_JITTER=3540                   # Maximum jitter in seconds (59 minutes)
# ===========================================================

# Ensure log file exists with secure permissions
touch "$LOG_FILE" 2>/dev/null || true
chmod 640 "$LOG_FILE" 2>/dev/null || true

# Logging function with timestamp
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log "=== MAC Changer started ==="

# ====================== JITTER ======================
JITTER_SECONDS=$(( RANDOM % (MAX_JITTER - MIN_JITTER + 1) + MIN_JITTER ))
log "Applying jitter: sleeping for $JITTER_SECONDS seconds (~$((JITTER_SECONDS / 60)) minutes)..."

# Use sleep in background so we can still be killed cleanly if needed
sleep "$JITTER_SECONDS" &
wait $!

# ====================== CHANGE MAC ADDRESSES ======================
for iface in "${INTERFACES[@]}"; do
    if ! ip link show "$iface" &>/dev/null; then
        log "Interface $iface not found - skipping"
        continue
    fi

    log "Changing MAC on $iface..."

    # Capture old MAC
    OLD_MAC=$(ip -brief link show "$iface" | awk '{print $3}' | head -n1)

    # Bring interface down
    ip link set dev "$iface" down 2>/dev/null || true
    sleep 1

    # Randomize MAC using macchanger
    if command -v macchanger >/dev/null 2>&1; then
        if ! macchanger -r "$iface" >> "$LOG_FILE" 2>&1; then
            log "WARNING: macchanger failed on $iface"
        fi
    else
        log "ERROR: macchanger command not found!"
        ip link set dev "$iface" up 2>/dev/null || true
        continue
    fi

    sleep 1

    # Bring interface back up
    ip link set dev "$iface" up 2>/dev/null || true
    sleep 2

    # Capture new MAC
    NEW_MAC=$(ip -brief link show "$iface" | awk '{print $3}' | head -n1)

    log "  Old: $OLD_MAC → New: $NEW_MAC"
done

# ====================== WI-FI RECONNECT ======================
if [[ " ${INTERFACES[*]} " =~ " ${WIFI_INTERFACE} " ]]; then
    if command -v nmcli >/dev/null 2>&1; then
        log "Reconnecting Wi-Fi interface ($WIFI_INTERFACE)..."
        nmcli device disconnect "$WIFI_INTERFACE" >/dev/null 2>&1 || true
        sleep 2
        nmcli device connect "$WIFI_INTERFACE" >/dev/null 2>&1 || true
        sleep 3
        log "Wi-Fi reconnect attempted"
    fi
fi

log "=== MAC Changer completed successfully ==="
echo "" >> "$LOG_FILE"
