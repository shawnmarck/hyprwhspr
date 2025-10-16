#!/bin/bash
# Complete restart script for hyprwhspr system

echo "🔄 Restarting hyprwhspr system..."
echo

# 1. Clean up any leftover status files
echo "1️⃣ Cleaning up status files..."
rm -f ~/.config/hyprwhspr/recording_status
rm -f ~/.config/hyprwhspr/current_status.json
echo "   ✅ Status files cleaned"

# 2. Restart hyprwhspr service
echo "2️⃣ Restarting hyprwhspr service..."
systemctl --user restart hyprwhspr.service
sleep 2
if systemctl --user is-active --quiet hyprwhspr.service; then
    echo "   ✅ Service running"
else
    echo "   ❌ Service not running!"
    systemctl --user status hyprwhspr.service --no-pager
fi

# 3. Restart Waybar
echo "3️⃣ Restarting Waybar..."
killall waybar 2>/dev/null
sleep 1
waybar &>/dev/null &
sleep 2
if pgrep -x waybar > /dev/null; then
    echo "   ✅ Waybar running"
else
    echo "   ❌ Waybar not running!"
fi

# 4. Reload Hyprland configuration
echo "4️⃣ Reloading Hyprland config..."
hyprctl reload > /dev/null
echo "   ✅ Hyprland config reloaded"

echo
echo "🎉 System restart complete!"
echo
echo "📊 Current Status:"
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh status
echo
echo "🧪 Test Instructions:"
echo "   1. Press ALT+SPACE → should turn RED 'REC'"
echo "   2. Press ALT+SPACE → should turn GREEN 'RDY'"
echo "   3. Or click the Waybar icon to toggle"
echo
