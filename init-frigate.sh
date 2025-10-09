#!/bin/bash

# Frigate macOS Local Deployment Initialization Script
# This script sets up /opt/frigate from the current project directory
# with backup and rollback functionality

set -o errexit -o nounset -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Backup configuration
BACKUP_DIR="/opt/frigate-backups"
BACKUP_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_PATH="${BACKUP_DIR}/frigate-backup-${BACKUP_TIMESTAMP}"

echo -e "${BLUE}[INFO]${NC} Initializing Frigate macOS Local Deployment..."

# Get current project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we can write to /opt or use user directory
if [[ -w "/opt" ]] || sudo -n true 2>/dev/null; then
    FRIGATE_DIR="/opt/frigate"
    USE_SUDO=true
    echo -e "${GREEN}[INFO]${NC} Using system directory: /opt/frigate"
else
    FRIGATE_DIR="$HOME/frigate-local"
    USE_SUDO=false
    echo -e "${YELLOW}[INFO]${NC} Cannot access /opt without password, using user directory: $HOME/frigate-local"
fi

# Update backup path based on chosen directory
if [[ "$USE_SUDO" == "true" ]]; then
    BACKUP_DIR="/opt/frigate-backups"
else
    BACKUP_DIR="$HOME/frigate-backups"
fi
BACKUP_PATH="${BACKUP_DIR}/frigate-backup-${BACKUP_TIMESTAMP}"

echo -e "${BLUE}[INFO]${NC} Project directory: ${PROJECT_DIR}"
echo -e "${BLUE}[INFO]${NC} Target directory: ${FRIGATE_DIR}"
echo -e "${BLUE}[INFO]${NC} Backup directory: ${BACKUP_PATH}"
echo -e "${BLUE}[INFO]${NC} Using sudo: ${USE_SUDO}"

# Rollback function
rollback() {
    echo -e "${RED}[ERROR]${NC} Installation failed! Rolling back changes..."
    
    if [[ -d "$BACKUP_PATH" ]]; then
        # Remove failed installation
        if [[ -d "$FRIGATE_DIR" ]]; then
            echo -e "${YELLOW}[ROLLBACK]${NC} Removing failed installation..."
            if [[ "$USE_SUDO" == "true" ]]; then
                sudo rm -rf "$FRIGATE_DIR"
            else
                rm -rf "$FRIGATE_DIR"
            fi
        fi
        
        # Restore from backup
        echo -e "${YELLOW}[ROLLBACK]${NC} Restoring from backup..."
        if [[ "$USE_SUDO" == "true" ]]; then
            sudo mv "$BACKUP_PATH" "$FRIGATE_DIR"
            sudo chown -R "$(whoami):staff" "$FRIGATE_DIR"
        else
            mv "$BACKUP_PATH" "$FRIGATE_DIR"
        fi
        
        echo -e "${GREEN}[ROLLBACK]${NC} Successfully restored from backup"
    else
        echo -e "${YELLOW}[ROLLBACK]${NC} No backup found, cleaning up failed installation..."
        if [[ -d "$FRIGATE_DIR" ]]; then
            if [[ "$USE_SUDO" == "true" ]]; then
                sudo rm -rf "$FRIGATE_DIR"
            else
                rm -rf "$FRIGATE_DIR"
            fi
        fi
    fi
    
    exit 1
}

# Set up error trap
trap rollback ERR

# Check if running from frigate project directory
if [[ ! -f "${PROJECT_DIR}/frigate/__init__.py" ]] || [[ ! -f "${PROJECT_DIR}/web/package.json" ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run from the Frigate project root directory"
    echo -e "${RED}[ERROR]${NC} Missing frigate/__init__.py or web/package.json"
    exit 1
fi

# Check for required tools
echo -e "${BLUE}[INFO]${NC} Checking required tools..."
for tool in uv python3 brew; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} Required tool '$tool' is not installed"
        exit 1
    fi
done

# Backup existing installation if present
if [[ -d "$FRIGATE_DIR" ]]; then
    echo -e "${YELLOW}[BACKUP]${NC} Existing installation found, creating backup..."
    if [[ "$USE_SUDO" == "true" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo cp -r "$FRIGATE_DIR" "$BACKUP_PATH"
    else
        mkdir -p "$BACKUP_DIR"
        cp -r "$FRIGATE_DIR" "$BACKUP_PATH"
    fi
    echo -e "${GREEN}[BACKUP]${NC} Backup created at: $BACKUP_PATH"
fi

# Create frigate directory structure
echo -e "${BLUE}[INFO]${NC} Creating directory structure..."
if [[ "$USE_SUDO" == "true" ]]; then
    sudo mkdir -p "$FRIGATE_DIR"
    sudo chown "$(whoami):staff" "$FRIGATE_DIR"
else
    mkdir -p "$FRIGATE_DIR"
fi

# Create subdirectories (mirroring Docker s6 overlay structure)
mkdir -p "${FRIGATE_DIR}"/{config,media,models,openvino-model,go2rtc,logs,db,tls,web-dist}

# Copy project files to frigate directory
echo -e "${BLUE}[INFO]${NC} Copying project files..."

# Copy Python source code
cp -r "${PROJECT_DIR}/frigate" "${FRIGATE_DIR}/"

# Copy web assets (will be built later)
cp -r "${PROJECT_DIR}/web" "${FRIGATE_DIR}/"

# Copy required files (using Docker main requirements as base)
cp "${PROJECT_DIR}/docker/main/requirements.txt" "${FRIGATE_DIR}/"
cp "${PROJECT_DIR}/pyproject.toml" "${FRIGATE_DIR}/"

# Copy Docker requirements for reference
cp "${PROJECT_DIR}/docker/main/requirements-wheels.txt" "${FRIGATE_DIR}/requirements-wheels.txt"

# Copy model conversion script
cp "${PROJECT_DIR}/docker/main/build_ov_model-mac.py" "${FRIGATE_DIR}/build_ov_model.py"
chmod +x "${FRIGATE_DIR}/build_ov_model.py"

# Create Python virtual environment using uv
echo -e "${BLUE}[INFO]${NC} Creating Python virtual environment with uv..."
cd "$FRIGATE_DIR"

# Create venv with Python 3.12
uv venv --python 3.12

# Activate virtual environment and install dependencies
echo -e "${BLUE}[INFO]${NC} Installing Python dependencies..."
source .venv/bin/activate

# Create macOS-specific requirements from wheels file (excluding problematic packages)
echo -e "${BLUE}[INFO]${NC} Creating macOS-specific requirements..."
grep -v -E "(nvidia-|openvino|onnxruntime-openvino)" requirements-wheels.txt > requirements-macos.txt

# Add macOS-specific packages
cat >> requirements-macos.txt << 'EOF'
# macOS-specific packages (replacing problematic ones)
onnxruntime==1.20.*
# Latest TensorFlow for Apple Silicon
tensorflow==2.18.*
# Latest OpenVINO
openvino==2025.2.*
# Additional packages for macOS deployment
py-vapid==1.9.*
pywebpush==2.0.*
pyclipper==1.3.*
shapely==2.0.*
Levenshtein==0.26.*
prometheus-client==0.21.*
EOF

# Install from macOS-specific requirements
uv pip install -r requirements-macos.txt

# Ensure development packages for model conversion
echo -e "${BLUE}[INFO]${NC} Installing additional development packages for OpenVINO model conversion..."
uv pip install tensorflow

echo -e "${BLUE}[INFO]${NC} Python dependencies installed successfully"

# Download models
echo -e "${BLUE}[INFO]${NC} Downloading AI models..."
cd "${FRIGATE_DIR}/models"

# Download CPU model for object detection
if [[ ! -f "cpu_model.tflite" ]]; then
    curl -L -o cpu_model.tflite "https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite"
    echo -e "${GREEN}[SUCCESS]${NC} Downloaded CPU detection model"
fi

# Download labelmaps (matching Docker rootfs structure)
if [[ ! -f "labelmap.txt" ]]; then
    curl -L -o labelmap.txt "https://raw.githubusercontent.com/blakeblackshear/frigate/dev/labelmap.txt"
    echo -e "${GREEN}[SUCCESS]${NC} Downloaded labelmap"
fi

if [[ ! -f "coco.txt" ]]; then
    curl -L -o coco.txt "https://raw.githubusercontent.com/blakeblackshear/frigate/dev/docker/main/rootfs/labelmap/coco.txt"
    echo -e "${GREEN}[SUCCESS]${NC} Downloaded COCO labelmap"
fi

# Convert and download OpenVINO model
echo -e "${BLUE}[INFO]${NC} Setting up OpenVINO model..."
cd "${FRIGATE_DIR}"
mkdir -p openvino-model

# Check if OpenVINO model files already exist
if [[ ! -f "openvino-model/ssdlite_mobilenet_v2.xml" ]] || [[ ! -f "openvino-model/ssdlite_mobilenet_v2.bin" ]]; then
    echo -e "${BLUE}[INFO]${NC} Converting TensorFlow model to OpenVINO format..."
    
    # Create models directory
    mkdir -p models
    cd models
    
    # Download TensorFlow model if not exists
    if [[ ! -f "ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz" ]]; then
        curl -L -o ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz "http://download.tensorflow.org/models/object_detection/ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz"
    fi
    
    # Extract TensorFlow model if not already extracted
    if [[ ! -d "ssdlite_mobilenet_v2_coco_2018_05_09" ]]; then
        tar -xzf ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz
    fi
    
    # Go back to main directory
    cd "${FRIGATE_DIR}"
    
    # Run model conversion with virtual environment activated (run only once)
    if python build_ov_model.py; then
        echo -e "${GREEN}[SUCCESS]${NC} OpenVINO model converted successfully"
    else
        echo -e "${RED}[ERROR]${NC} Model conversion failed, but continuing with setup..."
        echo -e "${YELLOW}[WARN]${NC} You may need to manually convert the model later"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} OpenVINO model already exists"
fi

# Download and process COCO labelmap for OpenVINO
if [[ ! -f "openvino-model/coco_91cl_bkgr.txt" ]]; then
    curl -L -o openvino-model/coco_91cl_bkgr.txt "https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt"
    # Replace 'truck' with 'car' in the labelmap (macOS compatible)
    sed -i '' 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt
    echo -e "${GREEN}[SUCCESS]${NC} Downloaded and processed OpenVINO COCO labelmap"
fi

# Download audio model
if [[ ! -f "cpu_audio_model.tflite" ]]; then
    echo -e "${BLUE}[INFO]${NC} Downloading audio model..."
    curl -L -o yamnet.tar.gz "https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download"
    tar -xzf yamnet.tar.gz && mv 1.tflite cpu_audio_model.tflite && rm yamnet.tar.gz
    echo -e "${GREEN}[SUCCESS]${NC} Downloaded audio model"
fi

# Download audio labelmap
if [[ ! -f "audio-labelmap.txt" ]]; then
    curl -L -o audio-labelmap.txt "https://raw.githubusercontent.com/blakeblackshear/frigate/dev/audio-labelmap.txt"
    echo -e "${GREEN}[SUCCESS]${NC} Downloaded audio labelmap"
fi

# Install go2rtc
echo -e "${BLUE}[INFO]${NC} Installing go2rtc..."
cd "${FRIGATE_DIR}/go2rtc"

if [[ ! -f "go2rtc" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        GOARCH="arm64"
    else
        GOARCH="amd64"
    fi
    
    curl -L -o go2rtc "https://github.com/AlexxIT/go2rtc/releases/download/v1.9.9/go2rtc_darwin_${GOARCH}"
    chmod +x go2rtc
    echo -e "${GREEN}[SUCCESS]${NC} Installed go2rtc"
else
    echo -e "${YELLOW}[SKIP]${NC} go2rtc already exists"
fi

# Build web frontend
echo -e "${BLUE}[INFO]${NC} Building web frontend..."
cd "${FRIGATE_DIR}/web"

# Check if Node.js/npm is available
if command -v npm &> /dev/null; then
    echo -e "${BLUE}[INFO]${NC} Installing Node.js dependencies..."
    npm install
    
    # Ensure TypeScript is available
    if ! npm list typescript &> /dev/null; then
        echo -e "${BLUE}[INFO]${NC} Installing TypeScript as development dependency..."
        npm install --save-dev typescript
    fi
    
    echo -e "${BLUE}[INFO]${NC} Building web frontend..."
    if npm run build; then
        # Copy built assets to web-dist
        if [[ -d "dist" ]]; then
            cp -r dist/* "${FRIGATE_DIR}/web-dist/"
            echo -e "${GREEN}[SUCCESS]${NC} Web frontend built successfully"
        else
            echo -e "${YELLOW}[WARN]${NC} Build succeeded but dist folder not found"
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} Web build failed, but continuing..."
        echo -e "${YELLOW}[WARN]${NC} Frigate API will still work without web frontend"
    fi
else
    echo -e "${YELLOW}[WARN]${NC} npm not found, skipping web build (Frigate API will still work)"
    echo -e "${YELLOW}[WARN]${NC} Install Node.js to enable web frontend: brew install node"
fi

# Create default configuration
echo -e "${BLUE}[INFO]${NC} Creating default configuration..."
cd "${FRIGATE_DIR}/config"

if [[ ! -f "config.yml" ]]; then
    cat > config.yml << EOF
# Frigate Configuration for macOS Local Deployment
# Generated by init-frigate.sh

# Database (local SQLite)
database:
  path: ${FRIGATE_DIR}/db/frigate.db

# Model configuration (OpenVINO CPU)
model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: ${FRIGATE_DIR}/openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: ${FRIGATE_DIR}/openvino-model/coco_91cl_bkgr.txt

# Detectors (OpenVINO CPU)
detectors:
  ov:
    type: openvino
    device: CPU

# Audio detection (optional)
audio:
  enabled: false  # Enable if you have microphones
  max_not_heard: 30
  listen:
    - bark
    - fire_alarm
    - scream
    - speech
    - yell

# MQTT (disable if not using Home Assistant)
mqtt:
  enabled: false
  # Uncomment and configure if using MQTT:
  # host: localhost
  # port: 1883
  # topic_prefix: frigate
  # client_id: frigate

# go2rtc configuration (WebRTC streaming)
go2rtc:
  streams: {}
    # Add your camera streams here, example:
    # backyard: rtsp://username:password@camera-ip/stream

# Global FFmpeg configuration (macOS optimized)
ffmpeg:
  # Use system FFmpeg from Homebrew
  global_args: -hide_banner -loglevel warning
  # Hardware acceleration for Apple Silicon (uncomment if needed)
  # hwaccel_args: 
  #   - -hwaccel
  #   - videotoolbox
  input_args: preset-rtsp-generic
  output_args:
    record: preset-record-generic-audio-copy

# Objects to detect
objects:
  track:
    - person
    - bicycle
    - car
    - motorcycle
    - bus
    - truck
    - bird
    - cat
    - dog

# Motion detection
motion:
  threshold: 30
  contour_area: 10
  delta_alpha: 0.2
  frame_alpha: 0.01
  frame_height: 50

# Recording configuration
record:
  enabled: false
  retain:
    days: 3
    mode: motion

# Live view
live:
  height: 720
  quality: 8

# Cameras (add your cameras here)
cameras: {}
  # Example camera:
  # backyard:
  #   ffmpeg:
  #     inputs:
  #       - path: rtsp://username:password@camera-ip/stream1
  #         roles:
  #           - detect
  #           - record
  #   detect:
  #     width: 1280
  #     height: 720
  #     fps: 5

# Version
version: 0.16-0
EOF
    echo -e "${GREEN}[SUCCESS]${NC} Created default config.yml"
else
    echo -e "${YELLOW}[SKIP]${NC} config.yml already exists"
fi

# Create go2rtc configuration
if [[ ! -f "go2rtc.yml" ]]; then
    cat > go2rtc.yml << EOF
# go2rtc Configuration for Frigate macOS Local
# Add your camera streams here

streams: {}
  # Example streams:
  # backyard: rtsp://username:password@camera-ip/stream

# WebRTC configuration
webrtc:
  candidates:
    - stun:8555

# API configuration
api:
  listen: ":1984"

# Logging
log:
  level: info
  output: /opt/frigate/logs/go2rtc.log
EOF
    echo -e "${GREEN}[SUCCESS]${NC} Created go2rtc.yml"
else
    echo -e "${YELLOW}[SKIP]${NC} go2rtc.yml already exists"
fi

# Create startup script
echo -e "${BLUE}[INFO]${NC} Creating startup script..."
cat > "${FRIGATE_DIR}/start-frigate.sh" << 'EOF'
#!/bin/bash

# Frigate macOS Local Startup Script
# Runs from /opt/frigate using project source code and uv venv

set -o errexit -o nounset -o pipefail

# Auto-detect Frigate installation directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRIGATE_DIR="$SCRIPT_DIR"
cd "$FRIGATE_DIR"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Starting Frigate macOS Local..."

# Activate virtual environment
source .venv/bin/activate

# Set environment variables for local development (not Docker)
export INSTALL_DIR="${FRIGATE_DIR}"
export CONFIG_FILE="${FRIGATE_DIR}/config/config.yml"
export CONFIG_DIR="${FRIGATE_DIR}/config"
export BASE_DIR="${FRIGATE_DIR}/media"
export DEFAULT_FFMPEG_VERSION="7.1"
export PATH="/opt/homebrew/bin:${FRIGATE_DIR}/go2rtc:$PATH"

# Disable warnings
export TOKENIZERS_PARALLELISM=true
export TRANSFORMERS_NO_ADVISORY_WARNINGS=1
export OPENCV_FFMPEG_LOGLEVEL=8

# Python path to include frigate module
export PYTHONPATH="${FRIGATE_DIR}:${PYTHONPATH:-}"

echo -e "${BLUE}[INFO]${NC} Environment configured"
echo -e "${BLUE}[INFO]${NC} Config: $CONFIG_FILE"
echo -e "${BLUE}[INFO]${NC} Media: $BASE_DIR"

# Start go2rtc in background
echo -e "${BLUE}[INFO]${NC} Starting go2rtc..."
${FRIGATE_DIR}/go2rtc/go2rtc -config ${FRIGATE_DIR}/config/go2rtc.yml > ${FRIGATE_DIR}/logs/go2rtc.log 2>&1 &
GO2RTC_PID=$!

# Wait for go2rtc to start
sleep 3

# Check if go2rtc started successfully
if ! kill -0 $GO2RTC_PID 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} go2rtc failed to start. Check logs at ${FRIGATE_DIR}/logs/go2rtc.log"
    exit 1
fi

echo -e "${GREEN}[SUCCESS]${NC} go2rtc started (PID: $GO2RTC_PID)"

# Start Frigate
echo -e "${BLUE}[INFO]${NC} Starting Frigate..."

# Cleanup function
cleanup() {
    echo -e "${BLUE}[INFO]${NC} Shutting down services..."
    if kill -0 $GO2RTC_PID 2>/dev/null; then
        kill $GO2RTC_PID
        wait $GO2RTC_PID 2>/dev/null || true
    fi
    echo -e "${BLUE}[INFO]${NC} Services stopped"
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start Frigate with logging
python -u -m frigate 2>&1 | tee ${FRIGATE_DIR}/logs/frigate.log

# Wait for background processes
wait $GO2RTC_PID
EOF

chmod +x "${FRIGATE_DIR}/start-frigate.sh"
echo -e "${GREEN}[SUCCESS]${NC} Created startup script"

# Create symlink for easy access
if [[ ! -L "$HOME/frigate" ]]; then
    ln -s "$FRIGATE_DIR" "$HOME/frigate"
    echo -e "${GREEN}[SUCCESS]${NC} Created symlink ~/frigate -> /opt/frigate"
fi

# Installation completed successfully - clean up backup on success
cleanup_backup() {
    if [[ -d "$BACKUP_PATH" ]]; then
        echo -e "${BLUE}[CLEANUP]${NC} Installation successful, removing backup..."
        if [[ "$USE_SUDO" == "true" ]]; then
            sudo rm -rf "$BACKUP_PATH"
        else
            rm -rf "$BACKUP_PATH"
        fi
        echo -e "${GREEN}[CLEANUP]${NC} Backup removed (installation successful)"
        
        # Clean up old backups (keep only last 3)
        if [[ -d "$BACKUP_DIR" ]]; then
            local backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "frigate-backup-*" -type d | wc -l)
            if [[ $backup_count -gt 3 ]]; then
                echo -e "${BLUE}[CLEANUP]${NC} Cleaning up old backups (keeping last 3)..."
                if [[ "$USE_SUDO" == "true" ]]; then
                    find "$BACKUP_DIR" -maxdepth 1 -name "frigate-backup-*" -type d | sort | head -n -3 | xargs sudo rm -rf
                else
                    find "$BACKUP_DIR" -maxdepth 1 -name "frigate-backup-*" -type d | sort | head -n -3 | xargs rm -rf
                fi
            fi
        fi
    fi
}

# Clear error trap before cleanup
trap - ERR

# Cleanup backup on successful installation
cleanup_backup

# Final setup summary
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Frigate macOS Local Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}Installation Directory:${NC} $FRIGATE_DIR"
echo -e "${BLUE}Quick Access Link:${NC} ~/frigate"
echo -e "${BLUE}Configuration:${NC} $FRIGATE_DIR/config/config.yml"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Configure your cameras in $FRIGATE_DIR/config/config.yml"
echo "2. Start Frigate: $FRIGATE_DIR/start-frigate.sh"
echo "3. Access web UI: http://localhost:5001"
echo
echo -e "${BLUE}Key Differences from Docker:${NC}"
echo "• No nginx proxy (FastAPI serves directly on port 5001)"
echo "• Uses uv for Python package management"
echo "• Uses Homebrew FFmpeg instead of custom build"
echo "• CPU-only inference (no GPU acceleration)"
echo "• Manual go2rtc installation (not bundled)"
echo
echo -e "${BLUE}Logs Location:${NC} $FRIGATE_DIR/logs/"
echo -e "${BLUE}Web Frontend:${NC} $([ -d "$FRIGATE_DIR/web-dist" ] && echo "Built" || echo "Skipped (install Node.js)")"
echo
echo -e "${BLUE}Backup Management:${NC}"
echo "• Backups stored in: $BACKUP_DIR"
echo "• On failure: Automatic rollback to previous version"
echo "• On success: Backup automatically removed"
echo "• Manual rollback: sudo mv $BACKUP_DIR/frigate-backup-TIMESTAMP $FRIGATE_DIR"
echo
echo "Happy monitoring! 📹"