#!/bin/bash
# hyprwhspr Continuous Status Monitor for Waybar

# Force unbuffered output
export PYTHONUNBUFFERED=1
exec stdbuf -oL -eL bash -c '

trap "exit 0" SIGTERM SIGINT

is_service_active() { 
    systemctl --user is-active --quiet hyprwhspr.service
}

is_recording() {
    is_service_active || return 1
    # Check for explicit recording status file (most reliable)
    local status_file="$HOME/.config/hyprwhspr/recording_status"
    if [[ -f "$status_file" ]]; then
        # Check file modification time to ensure it's recent (within last 3 seconds)
        local file_age
        file_age=$(($(date +%s) - $(stat -c %Y "$status_file" 2>/dev/null || echo 0)))
        if [[ "$file_age" -lt 3 ]]; then
            # File exists and is recent, read the status
            local status
            status="$(cat "$status_file" 2>/dev/null)"
            [[ "$status" == "recording" ]]
        else
            # File exists but is stale, remove it
            rm -f "$status_file" 2>/dev/null || true
            return 1
        fi
    else
        return 1
    fi
}

get_state() {
    if ! is_service_active; then
        systemctl --user is-failed --quiet hyprwhspr.service && echo "error" || echo "ready"
    elif is_recording; then
        echo "recording"
    else
        echo "ready"
    fi
}

last_state=""
while true; do
    current_state=$(get_state)
    if [[ "$current_state" != "$last_state" ]]; then
        case "$current_state" in
            "recording") echo "{\"text\":\"󰍬 REC\",\"class\":\"recording\",\"tooltip\":\"Recording\"}" ;;
            "ready") echo "{\"text\":\"󰍬 RDY\",\"class\":\"ready\",\"tooltip\":\"Ready\"}" ;;
            "error") echo "{\"text\":\"󰆉 ERR\",\"class\":\"error\",\"tooltip\":\"Error\"}" ;;
        esac
        last_state="$current_state"
    fi
    [[ "$current_state" == "recording" ]] && sleep 0.1 || sleep 0.5
done
'
