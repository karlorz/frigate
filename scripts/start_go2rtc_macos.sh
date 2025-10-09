#!/bin/bash
# macOS startup script for go2rtc in hybrid Frigate setup

set -e

# Configuration
FRIGATE_ROOT="/Users/karlchow/Desktop/code/frigate-local"
GO2RTC_BINARY="/Users/karlchow/go2rtc/go2rtc"
CONFIG_SCRIPT="${FRIGATE_ROOT}/scripts/create_go2rtc_config_working.py"
CONFIG_FILE="${FRIGATE_ROOT}/config/go2rtc.yaml"
LOG_FILE="${FRIGATE_ROOT}/logs/go2rtc.log"

# Create logs directory
mkdir -p "${FRIGATE_ROOT}/logs"

# Function to check if go2rtc is running
is_go2rtc_running() {
    pgrep -f "go2rtc.*config.*go2rtc.yaml" > /dev/null
}

# Function to stop existing go2rtc process
stop_go2rtc() {
    if is_go2rtc_running; then
        echo "[INFO] Stopping existing go2rtc process..."
        pkill -f "go2rtc.*config.*go2rtc.yaml" || true
        sleep 2
        if is_go2rtc_running; then
            echo "[WARN] Force killing go2rtc process..."
            pkill -9 -f "go2rtc.*config.*go2rtc.yaml" || true
            sleep 1
        fi
    fi
}

# Function to generate go2rtc config
generate_config() {
    echo "[INFO] Generating go2rtc configuration..."
    
    # Check if Python script exists
    if [[ ! -f "$CONFIG_SCRIPT" ]]; then
        echo "[ERROR] Config generation script not found: $CONFIG_SCRIPT"
        exit 1
    fi
    
    # Generate config
    cd "$FRIGATE_ROOT"
    python3 "$CONFIG_SCRIPT"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "[ERROR] Failed to generate config file: $CONFIG_FILE"
        exit 1
    fi
    
    echo "[INFO] Configuration generated at: $CONFIG_FILE"
}

# Function to start go2rtc
start_go2rtc() {
    echo "[INFO] Starting go2rtc..."
    
    # Check if binary exists
    if [[ ! -f "$GO2RTC_BINARY" ]]; then
        echo "[ERROR] go2rtc binary not found: $GO2RTC_BINARY"
        echo "[ERROR] Please ensure you have built go2rtc at this location"
        exit 1
    fi
    
    # Make binary executable
    chmod +x "$GO2RTC_BINARY"
    
    # Start go2rtc in background
    "$GO2RTC_BINARY" -config="$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
    GO2RTC_PID=$!
    
    echo "[INFO] go2rtc started with PID: $GO2RTC_PID"
    echo "[INFO] Logs available at: $LOG_FILE"
    
    # Wait a moment and check if it's running
    sleep 3
    if ! kill -0 $GO2RTC_PID 2>/dev/null; then
        echo "[ERROR] go2rtc failed to start. Check logs at: $LOG_FILE"
        tail -20 "$LOG_FILE"
        exit 1
    fi
    
    # Test if go2rtc is responding
    echo "[INFO] Testing go2rtc connectivity..."
    for i in {1..10}; do
        if curl -s http://localhost:1984/api/info > /dev/null; then
            echo "[INFO] go2rtc is responding on port 1984"
            break
        fi
        if [[ $i -eq 10 ]]; then
            echo "[WARN] go2rtc may not be fully ready yet (API not responding)"
        fi
        sleep 1
    done
    
    echo "[INFO] go2rtc startup complete"
    echo "[INFO] API available at: http://localhost:1984"
    echo "[INFO] To view logs: tail -f $LOG_FILE"
    echo "[INFO] To stop: pkill -f 'go2rtc.*config.*go2rtc.yaml'"
}

# Main execution
case "${1:-start}" in
    start)
        echo "[INFO] Starting go2rtc for Frigate hybrid setup..."
        stop_go2rtc
        generate_config
        start_go2rtc
        ;;
    stop)
        echo "[INFO] Stopping go2rtc..."
        stop_go2rtc
        echo "[INFO] go2rtc stopped"
        ;;
    restart)
        echo "[INFO] Restarting go2rtc..."
        stop_go2rtc
        generate_config
        start_go2rtc
        ;;
    status)
        if is_go2rtc_running; then
            echo "[INFO] go2rtc is running"
            echo "[INFO] PID(s): $(pgrep -f 'go2rtc.*config.*go2rtc.yaml')"
            if curl -s http://localhost:1984/api/info > /dev/null; then
                echo "[INFO] API is responding on port 1984"
            else
                echo "[WARN] API not responding on port 1984"
            fi
        else
            echo "[INFO] go2rtc is not running"
        fi
        ;;
    logs)
        if [[ -f "$LOG_FILE" ]]; then
            tail -f "$LOG_FILE"
        else
            echo "[ERROR] Log file not found: $LOG_FILE"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start go2rtc (default)"
        echo "  stop    - Stop go2rtc"
        echo "  restart - Restart go2rtc"
        echo "  status  - Check go2rtc status"
        echo "  logs    - View go2rtc logs"
        exit 1
        ;;
esac