#!/bin/bash

# HyprWhspr Omarchy/Arch Installation Script
# Automated installation for Hyprland + Arch Linux environments

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

# Configuration
PACKAGE_NAME="hyprwhspr"
INSTALL_DIR="/opt/hyprwhspr"
USER_CONFIG_DIR="$HOME/.config/hyprwhspr"
SERVICE_NAME="hyprwhspr.service"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root. It will use sudo when needed."
    exit 1
fi

# Check if we're on Arch Linux
if ! command -v pacman &> /dev/null; then
    log_error "This script is designed for Arch Linux systems. Please use the generic installation script instead."
    exit 1
fi

log_info "Starting HyprWhspr installation for Omarchy/Arch..."

# Function to install system dependencies
install_system_dependencies() {
    log_info "Installing system dependencies..."
    
    # Check what's already installed
    local packages_to_install=()
    
    # Core build tools
    for pkg in cmake make git base-devel; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        else
            log_info "$pkg already installed"
        fi
    done
    
    # Python tools
    for pkg in python; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        else
            log_info "$pkg already installed"
        fi
    done
    
    # Note: python-pip not required - will use venv's built-in pip
    log_info "python-pip not required - will use virtual environment's pip"
    
    # Audio tools
    for pkg in pipewire pipewire-alsa pipewire-pulse pipewire-jack; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        else
            log_info "$pkg already installed"
        fi
    done
    
    # Input tools
    if ! pacman -Q ydotool &>/dev/null; then
        packages_to_install+=("ydotool")
    else
        log_info "ydotool already installed"
    fi
    
    # Install missing packages if any
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${packages_to_install[*]}"
        sudo pacman -S --needed --noconfirm "${packages_to_install[@]}"
        log_success "System dependencies installed"
    else
        log_success "All system dependencies already installed"
    fi
}

# Function to setup Python virtual environment (like WhisperTux)
setup_python_environment() {
    log_info "Setting up Python virtual environment..."
    
    # Check if virtual environment exists
    if [ ! -d "$INSTALL_DIR/venv" ]; then
        log_info "Creating Python virtual environment..."
        python -m venv "$INSTALL_DIR/venv"
        log_success "Python virtual environment created"
    else
        log_info "Python virtual environment already exists"
    fi
    
    # Activate and install Python dependencies
    log_info "Activating virtual environment and installing dependencies..."
    source "$INSTALL_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install -r "$INSTALL_DIR/requirements.txt"
    
    log_success "Python dependencies installed"
}

# Function to clone and build whisper.cpp
setup_whisper() {
    log_info "Setting up whisper.cpp..."
    
    cd "$INSTALL_DIR"
    
    # Clone whisper.cpp if not present
    if [ ! -d "whisper.cpp" ]; then
        log_info "Cloning whisper.cpp repository..."
        git clone https://github.com/ggml-org/whisper.cpp.git
        log_success "whisper.cpp cloned successfully"
    else
        log_info "whisper.cpp directory already exists"
    fi
    
    cd "whisper.cpp"
    
    # Check if NVIDIA GPU is available for CUDA acceleration
    local use_cuda=false
    if command -v nvidia-smi &> /dev/null && command -v nvcc &> /dev/null; then
        log_info "NVIDIA GPU and CUDA toolkit detected - building with GPU acceleration"
        use_cuda=true
    else
        log_info "Building whisper.cpp with CPU-only support"
    fi
    
    # Build with CMake (modern build system)
    log_info "Building whisper.cpp with CMake..."
    cmake -B build
    
    # Add CUDA support if available
    if [ "$use_cuda" = true ]; then
        log_info "Configuring with CUDA support..."
        cmake -B build -DWHISPER_CUDA=ON -DCMAKE_BUILD_TYPE=Release
    fi
    
    cmake --build build -j --config Release
    
    # Verify binary was created
    if [ ! -f "build/bin/whisper-cli" ]; then
        log_error "Failed to build whisper.cpp binary"
        exit 1
    fi
    
    # Check if CUDA support was actually built in
    if [ "$use_cuda" = true ]; then
        if ldd build/bin/whisper-cli | grep -q cuda; then
            log_success "whisper.cpp built successfully with CUDA support"
        else
            log_warning "CUDA support requested but not detected in binary - falling back to CPU"
        fi
    else
        log_success "whisper.cpp built successfully (CPU-only)"
    fi
}

# Function to download default models
download_models() {
    log_info "Downloading default Whisper models..."
    
    cd "$INSTALL_DIR/whisper.cpp"
    
    # Download base.en model using the official method
    if [ ! -f "models/ggml-base.en.bin" ]; then
        log_info "Downloading base.en model..."
        sh ./models/download-ggml-model.sh base.en
        log_success "Base model downloaded"
    else
        log_info "Base model already exists"
    fi
    
    # Verify model exists (check both possible locations)
    if [ ! -f "models/ggml-base.en.bin" ] && [ ! -f "models/base.en.bin" ]; then
        log_error "Failed to download model. Installation cannot continue."
        exit 1
    fi
    
    log_success "Models verified and ready"
}

# Function to setup systemd service
setup_systemd_service() {
    log_info "Setting up systemd user service..."
    
    # Create user config directory if it doesn't exist
    mkdir -p "$HOME/.config/systemd/user"
    
    # Copy service file
    cp "$INSTALL_DIR/config/systemd/$SERVICE_NAME" "$HOME/.config/systemd/user/"
    
    # If we're installing from local directory, update the service paths
    if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
        log_info "Updating service paths for local installation..."
        sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$HOME/.config/systemd/user/$SERVICE_NAME"
        log_success "Service paths updated for local installation"
    fi
    
    # Reload systemd and enable service
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    
    log_success "Systemd service configured"
}

# Function to setup Hyprland integration
setup_hyprland_integration() {
    log_info "Setting up Hyprland integration..."
    
    # Create Hyprland config directory if it doesn't exist
    mkdir -p "$HOME/.config/hypr/scripts"
    
    # Copy tray script
    cp "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh" "$HOME/.config/hypr/scripts/"
    chmod +x "$HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
    
    # If we're installing from local directory, update the tray script paths
    if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
        log_info "Updating tray script paths for local installation..."
        sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
        log_success "Tray script paths updated for local installation"
    fi
    
    # Copy Waybar module
    mkdir -p "$HOME/.config/waybar"
    cp "$INSTALL_DIR/config/waybar/hyprwhspr-module.jsonc" "$HOME/.config/waybar/"
    
    # If we're installing from local directory, update the waybar module paths
    if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
        log_info "Updating waybar module paths for local installation..."
        sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$HOME/.config/waybar/hyprwhspr-module.jsonc"
        log_success "Waybar module paths updated for local installation"
    fi
    
    log_success "Hyprland integration configured"
}

# Function to setup waybar integration
setup_waybar_integration() {
    log_info "Setting up Waybar integration..."
    
    local waybar_config="$HOME/.config/waybar/config.jsonc"
    
    if [ -f "$waybar_config" ]; then
        # Check if hyprwhspr module is already in the config
        if ! grep -q "custom/hyprwhspr" "$waybar_config"; then
            log_info "Adding hyprwhspr module to waybar config..."
            
            # Add to modules-right array
            sed -i 's|"modules-right": \[|"modules-right": [\n    "custom/hyprwhspr",|g' "$waybar_config"
            
            # Add the module configuration at the end (before the closing brace)
            sed -i 's|}$|  "custom/hyprwhspr": {\n    "format": "{}",\n    "exec": "'"$INSTALL_DIR"'/config/hyprland/hyprwhspr-tray.sh status",\n    "interval": 2,\n    "return-type": "json",\n    "exec-on-event": true,\n    "on-click": "'"$INSTALL_DIR"'/config/hyprland/hyprwhspr-tray.sh toggle",\n    "on-click-right": "'"$INSTALL_DIR"'/config/hyprland/hyprwhspr-tray.sh start",\n    "on-click-middle": "'"$INSTALL_DIR"'/config/hyprland/hyprwhspr-tray.sh restart",\n    "tooltip": true\n  }\n}|' "$waybar_config"
            
            log_success "Waybar module added to config"
            
            # Copy CSS file for styling
            if [ -f "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" ]; then
                cp "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" "$HOME/.config/waybar/"
                log_success "CSS styling file copied to waybar config directory"
            fi
        else
            log_info "Hyprwhspr module already in waybar config"
        fi
    else
        log_warning "Waybar config not found at $waybar_config"
        log_info "You'll need to manually add the hyprwhspr module to your waybar config"
    fi
}

# Function to setup user configuration
setup_user_config() {
    log_info "Setting up user configuration..."
    
    mkdir -p "$USER_CONFIG_DIR"
    
    # Determine the actual model file path
    MODEL_PATH=""
    if [ -f "$INSTALL_DIR/whisper.cpp/models/ggml-base.en.bin" ]; then
        MODEL_PATH="$INSTALL_DIR/whisper.cpp/models/ggml-base.en.bin"
    elif [ -f "$INSTALL_DIR/whisper.cpp/models/base.en.bin" ]; then
        MODEL_PATH="$INSTALL_DIR/whisper.cpp/models/base.en.bin"
    else
        log_error "No Whisper model found. Cannot create configuration."
        return 1
    fi
    
    # Create default config if it doesn't exist
    if [ ! -f "$USER_CONFIG_DIR/config.json" ]; then
        cat > "$USER_CONFIG_DIR/config.json" << INNEREOF
{
    "primary_shortcut": "SUPER+ALT+D",
    "model": "$MODEL_PATH",
    "word_overrides": {}
}
INNEREOF
        log_success "Default configuration created with correct model path: $MODEL_PATH"
    else
        # Update existing config with correct model path
        log_info "Updating existing configuration with correct model path..."
        sed -i "s|\"model\": \"[^\"]*\"|\"model\": \"$MODEL_PATH\"|" "$USER_CONFIG_DIR/config.json"
        log_success "Configuration updated with correct model path: $MODEL_PATH"
    fi
}

# Function to setup permissions
setup_permissions() {
    log_info "Setting up user permissions..."
    
    # Add user to necessary groups
    sudo usermod -a -G input,audio "$USER"
    
    # Create udev rule for uinput access (critical for ydotool)
    if [ ! -f "/etc/udev/rules.d/99-uinput.rules" ]; then
        log_info "Creating uinput udev rule..."
        sudo tee /etc/udev/rules.d/99-uinput.rules > /dev/null << INNEREOF
# Allow members of the input group to access uinput device
KERNEL=="uinput", GROUP="input", MODE="0660"
INNEREOF
        
        # Reload udev rules
        sudo udevadm control --reload-rules
        sudo udevadm trigger --name-match=uinput
        
        log_success "uinput udev rule created and activated"
    else
        log_info "uinput udev rule already exists"
    fi
    
    # Load uinput module if needed
    if [ ! -e "/dev/uinput" ]; then
        log_info "Loading uinput kernel module..."
        sudo modprobe uinput
        log_success "uinput module loaded"
    fi
    
    log_warning "You may need to log out and back in for group changes to take effect"
}

# Function to detect and setup NVIDIA support
setup_nvidia_support() {
    log_info "Checking for NVIDIA GPU support..."
    
    if command -v nvidia-smi &> /dev/null; then
        log_success "NVIDIA GPU detected!"
        log_info "GPU Info:"
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
        
        # Check if CUDA toolkit is available
        if command -v nvcc &> /dev/null; then
            log_success "CUDA toolkit found - GPU acceleration will be available"
            log_info "Run the NVIDIA build script after installation for GPU acceleration:"
            log_info "  /opt/hyprwhspr/scripts/build-whisper-nvidia.sh"
        else
            log_warning "CUDA toolkit not found. Installing..."
            sudo pacman -S --needed --noconfirm cuda
            log_success "CUDA toolkit installed"
        fi
    else
        log_info "No NVIDIA GPU detected - CPU-only mode will be used"
    fi
}

# Function to setup audio devices
setup_audio_devices() {
    log_info "Setting up audio device configuration..."
    
    # Check PipeWire status
    if systemctl --user is-active --quiet pipewire; then
        log_success "PipeWire is running"
    else
        log_warning "PipeWire not running. Starting..."
        systemctl --user start pipewire
        systemctl --user start pipewire-pulse
        log_success "PipeWire started"
    fi
    
    # Check audio input devices
    log_info "Available audio input devices:"
    pactl list short sources | grep input || log_warning "No audio input devices found"
    
    log_info "Audio setup completed"
}

# Function to validate installation
validate_installation() {
    log_info "Validating installation..."
    
    # Check whisper.cpp binary (CMake build location)
    if [ ! -f "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" ]; then
        log_error "whisper.cpp binary not found. Installation incomplete."
        return 1
    fi
    
    # Check if GPU acceleration is available
    if ldd "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" | grep -q cuda; then
        log_success "whisper.cpp built with CUDA support - GPU acceleration available"
    else
        log_info "whisper.cpp built without CUDA - CPU-only mode"
    fi
    
    # Check model file (check both possible names)
    if [ ! -f "$INSTALL_DIR/whisper.cpp/models/ggml-base.en.bin" ] && [ ! -f "$INSTALL_DIR/whisper.cpp/models/base.en.bin" ]; then
        log_error "Whisper model not found. Installation incomplete."
        return 1
    fi
    
    # Check Python virtual environment
    if [ ! -f "$INSTALL_DIR/venv/bin/python" ]; then
        log_error "Python virtual environment not found. Installation incomplete."
        return 1
    fi
    
    # Check main application
    if [ ! -f "$INSTALL_DIR/lib/main.py" ]; then
        log_error "Main application not found. Installation incomplete."
        return 1
    fi
    
    log_success "Installation validation passed"
}

# Function to test installation
test_installation() {
    log_info "Testing installation..."
    
    # Validate first
    if ! validate_installation; then
        log_error "Installation validation failed. Cannot proceed with testing."
        return 1
    fi
    
    # Test if service can start
    if systemctl --user start "$SERVICE_NAME"; then
        log_success "Service started successfully"
        systemctl --user stop "$SERVICE_NAME"
    else
        log_error "Failed to start service"
        return 1
    fi
    
    # Test tray script
    if "$HOME/.config/hypr/scripts/hyprwhspr-tray.sh" status > /dev/null 2>&1; then
        log_success "Tray script working"
    else
        log_error "Tray script not working"
        return 1
    fi
    
    log_success "Installation test passed"
}

# Function to verify permissions and functionality
verify_permissions_and_functionality() {
    log_info "Verifying permissions and core functionality..."
    
    local all_tests_passed=true
    
    # Test 1: Check if user can access uinput device
    log_info "Testing uinput device access..."
    if [ -e "/dev/uinput" ]; then
        if [ -r "/dev/uinput" ] && [ -w "/dev/uinput" ]; then
            log_success "✓ uinput device accessible (read/write)"
        else
            log_error "✗ uinput device exists but not accessible"
            all_tests_passed=false
        fi
    else
        log_error "✗ /dev/uinput device not found"
        all_tests_passed=false
    fi
    
    # Test 2: Check if user is in required groups
    log_info "Testing user group membership..."
    if groups "$USER" | grep -q "\binput\b"; then
        log_success "✓ User in 'input' group"
    else
        log_error "✗ User NOT in 'input' group"
        all_tests_passed=false
    fi
    
    if groups "$USER" | grep -q "\baudio\b"; then
        log_success "✓ User in 'audio' group"
    else
        log_error "✗ User NOT in 'audio' group"
        all_tests_passed=false
    fi
    
    # Test 3: Test ydotool functionality
    log_info "Testing ydotool functionality..."
    if command -v ydotool &> /dev/null; then
        if timeout 5s ydotool help > /dev/null 2>&1; then
            log_success "✓ ydotool responds to commands"
        else
            log_error "✗ ydotool installed but not responding"
            all_tests_passed=false
        fi
    else
        log_error "✗ ydotool not installed"
        all_tests_passed=false
    fi
    
    # Test 4: Test audio device access
    log_info "Testing audio device access..."
    if command -v pactl &> /dev/null; then
        if pactl list short sources | grep -q input; then
            log_success "✓ Audio input devices detected"
        else
            log_warning "⚠ No audio input devices found"
        fi
    else
        log_warning "⚠ pactl not available - cannot verify audio devices"
    fi
    
    # Test 5: Test whisper.cpp functionality
    log_info "Testing whisper.cpp functionality..."
    if [ -f "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" ]; then
        if timeout 10s "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" --help > /dev/null 2>&1; then
            log_success "✓ whisper.cpp binary functional"
        else
            log_error "✗ whisper.cpp binary not responding"
            all_tests_passed=false
        fi
    else
        log_error "✗ whisper.cpp binary not found"
        all_tests_passed=false
    fi
    
    # Test 6: Test Python environment
    log_info "Testing Python environment..."
    if [ -f "$INSTALL_DIR/venv/bin/python" ]; then
        if timeout 5s "$INSTALL_DIR/venv/bin/python" -c "import sounddevice; print('Audio libraries available')" > /dev/null 2>&1; then
            log_success "✓ Python environment with audio libraries"
        else
            log_error "✗ Python environment missing audio libraries"
            all_tests_passed=false
        fi
    else
        log_error "✗ Python virtual environment not found"
        all_tests_passed=false
    fi
    
    # Test 7: Test systemd user service capability
    log_info "Testing systemd user service capability..."
    if systemctl --user is-enabled --quiet user.slice; then
        log_success "✓ User systemd services enabled"
    else
        log_warning "⚠ User systemd services may not be enabled"
    fi
    
    # Summary
    if [ "$all_tests_passed" = true ]; then
        log_success "All permission and functionality tests passed!"
        return 0
    else
        log_error "Some permission and functionality tests failed!"
        log_warning "HyprWhspr may not work correctly. Please check the errors above."
        return 1
    fi
}

# Main installation process
main() {
    log_info "Installing HyprWhspr to $INSTALL_DIR"
    
    # Check if already installed
    if [ -d "$INSTALL_DIR" ]; then
        log_warning "HyprWhspr appears to be already installed at $INSTALL_DIR"
        read -p "Do you want to continue with installation? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Create installation directory
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$USER" "$INSTALL_DIR"
    
    # Install system dependencies
    install_system_dependencies
    
    # Copy application files (assuming we're running from the source directory)
    log_info "Copying application files..."
    sudo cp -r . "$INSTALL_DIR/"
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    
    # Setup Python environment
    setup_python_environment
    
    # Setup whisper.cpp
    setup_whisper
    
    # Download models
    download_models
    
    # Setup systemd service
    setup_systemd_service
    
    # Setup Hyprland integration
    setup_hyprland_integration
    
    # Setup waybar integration
    setup_waybar_integration
    
    # Setup user configuration
    setup_user_config
    
    # Setup permissions
    setup_permissions
    
    # Detect NVIDIA support
    setup_nvidia_support

    # Setup audio devices
    setup_audio_devices
    
    # Validate installation
    validate_installation
    
    # Verify permissions and functionality
    verify_permissions_and_functionality
    
    # Test installation
    test_installation
    
    log_success "HyprWhspr installation completed successfully!"
    
    # Show GPU acceleration status
    if ldd "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" | grep -q cuda; then
        log_success "✅ GPU acceleration is ENABLED - NVIDIA CUDA support active"
    else
        log_info "ℹ️  GPU acceleration is DISABLED - CPU-only mode"
        if command -v nvidia-smi &> /dev/null; then
            log_info "💡 NVIDIA GPU detected - you can rebuild with GPU support using:"
            log_info "   /opt/hyprwhspr/scripts/build-whisper-nvidia.sh"
        fi
    fi
    
    log_info ""
    log_info "Next steps:"
    log_info "1. Log out and back in (or reboot) for group changes to take effect"
    log_info "2. Waybar module automatically added to your config"
    log_info "3. Add CSS styling to your waybar style.css:"
    log_info "   @import \"$INSTALL_DIR/config/waybar/hyprwhspr-style.css\";"
    log_info "4. Use Super+Alt+D to start dictation"
    log_info "5. Check system tray for status with animations"
    log_info ""
    log_info "The service will start automatically on login"
    log_info ""
    log_info "Troubleshooting:"
    log_info "• If you encounter permission issues, run: /opt/hyprwhspr/scripts/fix-uinput-permissions.sh"
    log_info "• If GPU acceleration isn't working, run: /opt/hyprwhspr/scripts/build-whisper-nvidia.sh"
    log_info "• Check logs: journalctl --user -u hyprwhspr.service"
}

# Run main function
main "$@"
