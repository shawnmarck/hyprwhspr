#!/bin/bash

# hyprwhspr - uinput Permissions Fix
# This script creates the necessary udev rule and adds the user to required groups
# for ydotool to work without root privileges

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "hyprwhspr - uinput Permissions Fix"
echo "=================================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Do not run this script as root!"
    log_error "Run as your normal user - the script will use sudo when needed."
    exit 1
fi

# Check if ydotool is installed
if ! command -v ydotool &> /dev/null; then
    log_warning "ydotool is not installed!"
    log_info "Please install ydotool first:"
    echo ""
    echo "Ubuntu/Debian: sudo apt install ydotool"
    echo "Fedora:        sudo dnf install ydotool" 
    echo "Arch:          sudo pacman -S ydotool"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Current situation:"
echo "------------------"

# Check current groups
echo "Your current groups: $(groups)"

# Check if in input group
if groups "$USER" | grep -q "\binput\b"; then
    echo "✓ You are already in the 'input' group"
else
    echo "✗ You are NOT in the 'input' group"
fi

# Check if in tty group
if groups "$USER" | grep -q "\btty\b"; then
    echo "✓ You are already in the 'tty' group"
else
    echo "✗ You are NOT in the 'tty' group"
fi

# Check udev rule
if [ -f "/etc/udev/rules.d/99-uinput.rules" ]; then
    echo "✓ uinput udev rule exists"
    echo "   Content: $(cat /etc/udev/rules.d/99-uinput.rules)"
else
    echo "✗ uinput udev rule does NOT exist"
fi

# Check /dev/uinput permissions
if [ -e "/dev/uinput" ]; then
    echo "Current /dev/uinput permissions: $(ls -la /dev/uinput)"
else
    echo "✗ /dev/uinput device does not exist"
fi

echo ""
echo "Applying fixes:"
echo "---------------"

# Add user to groups
groups_added=false
if ! groups "$USER" | grep -q "\binput\b"; then
    echo "Adding user $USER to 'input' group..."
    sudo usermod -a -G input "$USER"
    groups_added=true
fi

if ! groups "$USER" | grep -q "\btty\b"; then
    echo "Adding user $USER to 'tty' group..."
    sudo usermod -a -G tty "$USER"
    groups_added=true
fi

# Create udev rule
if [ ! -f "/etc/udev/rules.d/99-uinput.rules" ]; then
    echo "Creating uinput udev rule..."
    sudo tee /etc/udev/rules.d/99-uinput.rules << 'EOF'
# Allow members of the input group to access uinput device
KERNEL=="uinput", GROUP="input", MODE="0660"
EOF
    echo "✓ udev rule created"
    
    echo "Reloading udev rules..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=uinput
    echo "✓ udev rules reloaded"
else
    echo "✓ uinput udev rule already exists"
fi

# Check if we need to create /dev/uinput
if [ ! -e "/dev/uinput" ]; then
    echo "Creating /dev/uinput device..."
    sudo modprobe uinput
    echo "✓ uinput module loaded"
fi

echo ""
echo "Summary:"
echo "--------"

if [ "$groups_added" = true ]; then
    log_warning "You have been added to new groups."
    log_warning "You need to log out and back in (or reboot) for group changes to take effect."
    echo ""
fi

echo "✓ uinput udev rule configured"
echo "✓ User groups configured"
echo "✓ uinput module loaded"

echo ""
log_success "uinput permissions fix completed!"
echo ""
echo "Next steps:"
echo "1. Log out and back in (or reboot) for group changes to take effect"
echo "2. Test ydotool: ydotool help"
echo "3. If ydotool works, hyprwhspr should work without permission issues"
echo ""
echo "If you still have issues after logging back in, run:"
echo "  sudo udevadm control --reload-rules"
echo "  sudo udevadm trigger"
