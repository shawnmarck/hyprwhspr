#!/bin/bash

# hyprwhspr System Tray Status Script
# Shows hyprwhspr status in the Hyprland system tray with JSON output

PACKAGE_ROOT="/opt/hyprwhspr"
ICON_PATH="$PACKAGE_ROOT/share/assets/hyprwhspr.png"

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
    
    # Method 1: Check for actual audio input activity (most reliable)
    if pactl list short sources 2>/dev/null | grep -q "alsa_input.*RUNNING" 2>/dev/null; then
        # Additional check: verify there's actual audio data flowing
        if pactl list short sources 2>/dev/null | grep -q "alsa_input.*RUNNING.*[0-9]\+Hz" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Method 2: Check for active audio capture processes (more reliable)
    if pgrep -f "hyprwhspr" > /dev/null 2>&1; then
        # Check if the hyprwhspr process is actively using audio devices
        if lsof /dev/snd/* 2>/dev/null | grep -q "hyprwhspr.*r" 2>/dev/null; then
            return 0
        fi
        
        # Alternative: check if Python process is consuming audio
        if lsof /dev/snd/* 2>/dev/null | grep -q "python.*r" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Method 3: Check for sounddevice or portaudio processes
    if pgrep -f "sounddevice\|portaudio" > /dev/null 2>&1; then
        return 0
    fi
    
    # Method 4: Check for any Python process with actual audio device file descriptors
    if pgrep -f "python.*hyprwhspr" > /dev/null 2>&1; then
        # Check if it has actual audio device file descriptors open (not just library files)
        local python_pid=$(pgrep -f "python.*hyprwhspr" | head -1)
        if [ -n "$python_pid" ]; then
            # Only look for actual /dev/snd device files, not library paths
            if lsof -p "$python_pid" 2>/dev/null | grep -q "^.*[0-9]*[rw].*[0-9]*[0-9]* /dev/snd/"; then
                return 0
            fi
        fi
    fi
    
    # Method 5: Check for PipeWire audio activity (hyprwhspr might use PipeWire client API)
    if pactl list short sources 2>/dev/null | grep -q "alsa_input.*RUNNING\|pipewire.*RUNNING" 2>/dev/null; then
        return 0
    fi
    
    # Method 6: Check for any recent audio activity in system
    if lsof /dev/snd/* 2>/dev/null | grep -q "python.*r\|hyprwhspr.*r"; then
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
        systemctl --user start ydotool.service
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

# Function to emit JSON output for waybar
emit_json() {
    local state="$1"
    local icon text tooltip
    
    case "$state" in
        "recording")
            icon="󰍬"
            text="$icon REC"
            tooltip="hyprwhspr: Currently recording\n\nLeft-click: Stop recording\nRight-click: Restart\nMiddle-click: Restart"
            ;;
        "error")
            icon="󰆉"
            text="$icon ERR"
            tooltip="hyprwhspr: Issue detected\n\nLeft-click: Toggle service\nRight-click: Start service\nMiddle-click: Restart service"
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
            state="error"
            ;;
    esac
    
    # Output JSON for waybar
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$state" "$tooltip"
}

# Function to get current state
get_current_state() {
    # Check service health first
    check_service_health
    
    if is_hyprwhspr_running; then
        if is_hyprwhspr_recording; then
            echo "recording"
        else
            # Ready state - check if ydotool is working
            if is_ydotoold_running; then
                echo "ready"
            else
                echo "error"
            fi
        fi
    else
        # Not running state
        if is_ydotoold_running; then
            echo "error"
        else
            echo "error"
        fi
    fi
}

# Main menu
case "${1:-status}" in
    "status")
        emit_json "$(get_current_state)"
        ;;
    "toggle")
        toggle_hyprwhspr
        emit_json "$(get_current_state)"
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
        emit_json "$(get_current_state)"
        ;;
    "stop")
        if is_hyprwhspr_running; then
            systemctl --user stop hyprwhspr.service
            show_notification "hyprwhspr" "Stopped" "low"
        fi
        emit_json "$(get_current_state)"
        ;;
    "ydotoold")
        start_ydotoold
        emit_json "$(get_current_state)"
        ;;
    "restart")
        systemctl --user restart hyprwhspr.service
        show_notification "hyprwhspr" "Restarted" "normal"
        emit_json "$(get_current_state)"
        ;;
    "health")
        check_service_health
        if [ $? -eq 0 ]; then
            echo "Service health check passed"
        else
            echo "Service health check failed, attempting recovery"
        fi
        emit_json "$(get_current_state)"
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
