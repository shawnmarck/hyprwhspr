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
    pgrep -f "hyprwhspr" >/dev/null 2>&1 || return 1
    local state
    state=$(pactl list sources short | grep "$(pactl get-default-source 2>/dev/null)" | awk "{print \$NF}")
    [[ "$state" == "RUNNING" ]]
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
