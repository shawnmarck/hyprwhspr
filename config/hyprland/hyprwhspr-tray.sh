#!/bin/bash

# hyprwhspr System Tray Status Script
# Shows hyprwhspr status in the Hyprland system tray with JSON output

PACKAGE_ROOT="/opt/hyprwhspr"
ICON_PATH="$PACKAGE_ROOT/share/assets/hyprwhspr.png"

# Performance optimization: command caching
_now=$(date +%s%3N 2>/dev/null || date +%s)  # ms if available
declare -A _cache

# Cached command execution with timeout
cmd_cached() {
    local key="$1" ttl_ms="${2:-500}" cmd="${3}"; shift 3 || true
    local now=$(_date_ms)
    if [[ -n "${_cache[$key.time]:-}" && $((now - _cache[$key.time])) -lt $ttl_ms ]]; then
        printf '%s' "${_cache[$key.val]}"; return 0
    fi
    local out
    out=$(timeout 0.25s bash -c "$cmd" 2>/dev/null) || out=""
    _cache[$key.val]="$out"; _cache[$key.time]=$now
    printf '%s' "$out"
}

_date_ms(){ date +%s%3N 2>/dev/null || date +%s; }

# Function to check if hyprwhspr is running
is_hyprwhspr_running() {
    systemctl --user is-active --quiet hyprwhspr.service
}

# Function to check if ydotoold is running and working
is_ydotoold_running() {
    # Check if service is active
    if systemctl --user is-active --quiet ydotoold.service; then
        # Test if ydotool actually works by using a simple command
        timeout 1s ydotool help > /dev/null 2>&1
        return $?
    fi
    return 1
}

# Function to check PipeWire health comprehensively
is_pipewire_ok() {
    timeout 0.2s pactl info >/dev/null 2>&1 || return 1
    pactl list short sources 2>/dev/null | grep -qE 'RUNNING|input' || return 1
    return 0
}

# Function to check if model file exists
model_exists() {
    local cfg="$HOME/.config/hyprwhspr/config.json"
    local model_path
    model_path=$(grep -oE '"model"\s*:\s*"[^"]+"' "$cfg" 2>/dev/null | cut -d\" -f4)
    [[ -n "$model_path" ]] || return 0  # use defaults; skip
    [[ -f "$model_path" ]] || return 1
}

# Function to check if we can actually start recording
can_start_recording() {
    # Check if microphone is available and accessible
    if ! pactl list short sources 2>/dev/null | grep -q "alsa_input"; then
        return 1
    fi
    
    # Check if we can actually access the audio device
    if ! lsof /dev/snd/* 2>/dev/null | grep -q "alsa_input"; then
        return 1
    fi
    
    # Check if audio input is not already in use by another process
    if lsof /dev/snd/* 2>/dev/null | grep -q "whisper\|hyprwhspr" | grep -q "r"; then
        return 1
    fi
    
    return 0
}

# Function to check if hyprwhspr is currently recording
is_hyprwhspr_recording() {
    # Check if hyprwhspr is running
    if ! is_hyprwhspr_running; then
        return 1
    fi
    
    # Method 1: Check for actual audio input activity (most reliable) - cached
    if [[ -n "$(cmd_cached pactl_sources 500 "pactl list short sources | grep -E 'alsa_input.*RUNNING'")" ]]; then
        # Additional check: verify there's actual audio data flowing
        if [[ -n "$(cmd_cached pactl_sources_hz 500 "pactl list short sources | grep -E 'alsa_input.*RUNNING.*[0-9]+Hz'")" ]]; then
            return 0
        fi
    fi
    
    # Method 2: Check for active audio capture processes (more reliable) - cached
    if [[ -n "$(cmd_cached pgrep_hyprwhspr 500 "pgrep -f 'hyprwhspr'")" ]]; then
        # Check if the hyprwhspr process is actively using audio devices
        if [[ -n "$(cmd_cached lsof_snd_hyprwhspr 500 "lsof /dev/snd/* | grep -E 'hyprwhspr.*r'")" ]]; then
            return 0
        fi
        
        # Alternative: check if Python process is consuming audio
        if [[ -n "$(cmd_cached lsof_snd_python 500 "lsof /dev/snd/* | grep -E 'python.*r'")" ]]; then
            return 0
        fi
    fi
    
    # Method 3: Check for sounddevice or portaudio processes - cached
    if [[ -n "$(cmd_cached pgrep_audio_libs 500 "pgrep -f 'sounddevice|portaudio'")" ]]; then
        return 0
    fi
    
    # Method 4: Check for any Python process with actual audio device file descriptors - cached
    local python_pid=$(cmd_cached pgrep_python_hyprwhspr 500 "pgrep -f 'python.*hyprwhspr' | head -1")
    if [ -n "$python_pid" ]; then
        # Only look for actual /dev/snd device files, not library paths
        if [[ -n "$(cmd_cached lsof_python_pid 500 "lsof -p $python_pid | grep -E '^.*[0-9]*[rw].*[0-9]*[0-9]* /dev/snd/'")" ]]; then
            return 0
        fi
    fi
    
    # Method 5: Check for PipeWire audio activity (hyprwhspr might use PipeWire client API) - cached
    if [[ -n "$(cmd_cached pactl_pipewire 500 "pactl list short sources | grep -E 'alsa_input.*RUNNING|pipewire.*RUNNING'")" ]]; then
        return 0
    fi
    
    # Method 6: Check for any recent audio activity in system - cached
    if [[ -n "$(cmd_cached lsof_snd_any 500 "lsof /dev/snd/* | grep -E 'python.*r|hyprwhspr.*r'")" ]]; then
        return 0
    fi
    
    return 1
}



# Function to show notification
show_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    if command -v notify-send &> /dev/null; then
        notify-send -i "$ICON_PATH" "$title" "$message" -u "$urgency"
    fi
}

# Function to toggle hyprwhspr
toggle_hyprwhspr() {
    if is_hyprwhspr_running; then
        echo "Stopping hyprwhspr..."
        systemctl --user stop hyprwhspr.service
        show_notification "hyprwhspr" "Stopped" "low"
    else
        if can_start_recording; then
            echo "Starting hyprwhspr..."
            systemctl --user start hyprwhspr.service
            show_notification "hyprwhspr" "Started" "normal"
        else
            echo "Cannot start hyprwhspr - no microphone available"
            show_notification "hyprwhspr" "No microphone available" "critical"
            return 1
        fi
    fi
}

# Function to start ydotoold if needed
start_ydotoold() {
    if ! is_ydotoold_running; then
        echo "Starting ydotoold..."
        systemctl --user start ydotoold.service  # Fixed: was ydotool.service
        sleep 1
        if is_ydotoold_running; then
            show_notification "hyprwhspr" "ydotoold started" "low"
        else
            show_notification "hyprwhspr" "Failed to start ydotoold" "critical"
        fi
    fi
}

# Function to check service health and recover from stuck states
check_service_health() {
    if is_hyprwhspr_running; then
        # Check if service has been in "activating" state too long
        local service_status=$(systemctl --user show hyprwhspr.service --property=ActiveState --value)
        
        if [ "$service_status" = "activating" ]; then
            # Service is stuck starting, restart it
            echo "Service stuck in activating state, restarting..."
            systemctl --user restart hyprwhspr.service
            return 1
        fi
        
        # Check if recording state is stuck (running but no actual audio)
        if is_hyprwhspr_running && ! is_hyprwhspr_recording; then
            # Service is running but not recording - this is normal
            return 0
        fi
    fi
    return 0
}

# Function to emit JSON output for waybar with granular error classes
emit_json() {
    local state="$1" reason="${2:-}"
    local icon text tooltip class="$state"
    
    case "$state" in
        "recording")
            icon="󰍬"
            text="$icon REC"
            tooltip="hyprwhspr: Currently recording\n\nLeft-click: Stop recording\nRight-click: Restart\nMiddle-click: Restart"
            ;;
        "error")
            icon="󰆉"
            text="$icon ERR"
            tooltip="hyprwhspr: Issue detected${reason:+ ($reason)}\n\nLeft-click: Toggle service\nRight-click: Start service\nMiddle-click: Restart service"
            class="error ${reason}"
            ;;
        "ready")
            icon="󰍬"
            text="$icon RDY"
            tooltip="hyprwhspr: Ready to record\n\nLeft-click: Start recording\nRight-click: Start service\nMiddle-click: Restart service"
            ;;
        *)
            icon="󰆉"
            text="$icon"
            tooltip="hyprwhspr: Unknown state\n\nLeft-click: Toggle service\nRight-click: Start service\nMiddle-click: Restart service"
            class="error unknown"
            state="error"
            ;;
    esac
    
    # Output JSON for waybar
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$tooltip"
}

# Function to get current state with detailed error reasons
get_current_state() {
    local reason=""
    
    # Check service health first
    check_service_health
    
    # Check if service is running
    if ! systemctl --user is-active --quiet hyprwhspr.service; then
        # Distinguish failed from inactive
        if systemctl --user is-failed --quiet hyprwhspr.service; then
            local result exec_code
            result=$(systemctl --user show hyprwhspr.service -p Result --value 2>/dev/null)
            exec_code=$(systemctl --user show hyprwhspr.service -p ExecMainStatus --value 2>/dev/null)
            reason="service_failed:${result:-unknown}:${exec_code:-}"
        else
            reason="service_inactive"
        fi
        echo "error:$reason"; return
    fi
    
    # Service is running - check if recording
    if is_hyprwhspr_recording; then
        echo "recording"; return
    fi
    
    # Service running but not recording - check dependencies
    if ! is_ydotoold_running; then
        echo "error:ydotoold"; return
    fi
    
    # Check PipeWire health
    if ! is_pipewire_ok; then
        echo "error:pipewire_down"; return
    fi
    
    # Check model existence
    if ! model_exists; then
        echo "error:model_missing"; return
    fi
    
    echo "ready"
}

# Main menu
case "${1:-status}" in
    "status")
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    "toggle")
        toggle_hyprwhspr
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    "start")
        if ! is_hyprwhspr_running; then
            if can_start_recording; then
                systemctl --user start hyprwhspr.service
                show_notification "hyprwhspr" "Started" "normal"
            else
                show_notification "hyprwhspr" "No microphone available" "critical"
            fi
        fi
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    "stop")
        if is_hyprwhspr_running; then
            systemctl --user stop hyprwhspr.service
            show_notification "hyprwhspr" "Stopped" "low"
        fi
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    "ydotoold")
        start_ydotoold
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    "restart")
        systemctl --user restart hyprwhspr.service
        show_notification "hyprwhspr" "Restarted" "normal"
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    "health")
        check_service_health
        if [ $? -eq 0 ]; then
            echo "Service health check passed"
        else
            echo "Service health check failed, attempting recovery"
        fi
        IFS=: read -r s r <<<"$(get_current_state)"
        emit_json "$s" "$r"
        ;;
    *)
        echo "Usage: $0 [status|toggle|start|stop|ydotoold|restart|health]"
        echo ""
        echo "Commands:"
        echo "  status    - Show current status (JSON output)"
        echo "  toggle    - Toggle hyprwhspr on/off"
        echo "  start     - Start hyprwhspr"
        echo "  stop      - Stop hyprwhspr"
        echo "  ydotoold  - Start ydotoold daemon"
        echo "  restart   - Restart hyprwhspr"
        echo "  health    - Check service health and recover if needed"
        ;;
esac
