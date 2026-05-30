#!/bin/sh
# scripts/start_desktop.sh
# Startup helper script to launch a graphical desktop environment (Openbox) in AULinux.

set -e

echo "=================================================="
echo "       AULinux Desktop Startup Helper             "
echo "=================================================="

# 1. Register and map environment variables & dynamic linker paths
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib
export HOME=/root
export USER=root
export DISPLAY=:0

echo "[1/4] Environment variables and dynamic library paths registered:"
echo "      PATH=$PATH"
echo "      LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

# 2. Check and install necessary graphics packages using aupkg
echo ""
echo "[2/4] Verifying graphical desktop package stack..."

# We attempt to run openbox. If not found, we install openbox and xf86-video-fbdev.
# Because openbox and xf86-video-fbdev depend on xorg-server, and xorg-server
# depends on libinput, aupkg will automatically resolve and install all four!
if ! command -v openbox >/dev/null 2>&1; then
    echo "      Openbox is not installed. Spawning aupkg to install graphics environment..."
    echo "      This will automatically resolve dependencies: openbox -> xorg-server -> libinput"
    
    # Run aupkg install
    aupkg install openbox xf86-video-fbdev
    
    echo "      Package installation complete."
else
    echo "      Graphics environment already installed."
fi

# 3. Boot the X server session
echo ""
echo "[3/4] Initializing X.Org Server with frame-buffer device driver (fbdev)..."

if [ -f /usr/bin/Xorg ]; then
    # Start Xorg server in the background
    # We pass the fbdev configuration and run on display :0
    /usr/bin/Xorg :0 -config /etc/X11/xorg.conf > /var/log/xorg.log 2>&1 &
    XSERVER_PID=$!
    
    # Wait briefly for X server to spin up
    sleep 2
    
    if kill -0 $XSERVER_PID >/dev/null 2>&1; then
        echo "      X.Org Server started successfully (PID: $XSERVER_PID)."
    else
        echo "      Error: X.Org Server failed to start. Check /var/log/xorg.log"
        exit 1
    fi
else
    echo "      Error: /usr/bin/Xorg executable not found!"
    exit 1
fi

# 4. Start the Openbox Window Manager session
echo ""
echo "[4/4] Starting Openbox graphical window manager session..."
echo "      To exit the desktop session and return to shell, close Openbox or exit the terminal."
echo "      ------------------------------------------------------------------------"

# Run Openbox with the mock configuration file
if command -v openbox >/dev/null 2>&1; then
    openbox --config-file /etc/xdg/openbox/rc.xml
else
    echo "      Error: openbox executable not found!"
    exit 1
fi

# Cleanup after desktop exit
echo ""
echo "Desktop session ended. Cleaning up X server..."
kill $XSERVER_PID 2>/dev/null || true
echo "Cleanup complete. Returning to AULinux shell."
echo "=================================================="
