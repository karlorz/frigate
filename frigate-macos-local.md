# Frigate macOS Local Deployment Guide

This guide explains how to run Frigate locally on macOS without Docker, using the current project source code and native macOS tools. This approach avoids Docker containerization and go2rtc FFmpeg version conflicts while maintaining full functionality.

## Key Differences from Docker Deployment

| Component | Docker Version | macOS Local Version |
|-----------|---------------|-------------------|
| **Web Server** | nginx proxy (port 8971) | Direct FastAPI (port 5001) |
| **Python Environment** | Container python | uv-managed virtual environment |
| **FFmpeg** | Custom compiled build | Homebrew FFmpeg 7.1+ |
| **go2rtc** | Bundled in container | Separate binary installation |
| **File Structure** | `/opt/frigate` in container | `/opt/frigate` on macOS |
| **Process Management** | s6-overlay services | macOS startup script |
| **Configuration** | Docker volumes | Direct file access |
| **Updates** | Container rebuild | `git pull` + script |

## Quick Setup (Recommended)

**Prerequisites**: Ensure you have Homebrew and basic development tools installed.

1. **Clone/Navigate to Frigate Project**:
   ```bash
   # If you haven't cloned the project yet:
   # git clone https://github.com/blakeblackshear/frigate.git
   cd /path/to/your/frigate-project
   ```

2. **Install System Dependencies**:
   ```bash
   # Install required tools and FFmpeg
   brew install ffmpeg python@3.12 uv cmake pkg-config
   brew install sqlite3 yq jq curl node  # node is optional for web UI
   ```

3. **Run Initialization Script**:
   ```bash
   ./init-frigate.sh
   ```
   
   This script will:
   - Set up `/opt/frigate` directory structure
   - Copy project files from current directory
   - Create uv virtual environment with all dependencies
   - Download AI models and labelmaps
   - Install go2rtc binary
   - Build web frontend (if Node.js available)
   - Create default configuration files
   - Generate startup script

4. **Configure and Start**:
   ```bash
   # Edit configuration (add your cameras)
   nano /opt/frigate/config/config.yml
   
   # Start Frigate
   /opt/frigate/start-frigate.sh
   ```
   
   Access the web interface at: **http://localhost:5001**

## Manual Setup (Advanced)

### System Requirements
- macOS (tested on macOS 15+)
- Python 3.11 or 3.12 (Python 3.12+ recommended)
- Homebrew package manager
- At least 4GB RAM
- Storage for recordings and model files
- Current Frigate project source code

### Install Dependencies

#### 1. Install Homebrew (if not already installed)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### 2. Install Core Dependencies
```bash
# Install FFmpeg (replaces Docker custom build)
brew install ffmpeg

# Install Python and uv (replaces Docker python environment)
brew install python@3.12 uv

# Install system dependencies
brew install cmake pkg-config sqlite3 yq jq curl

# Optional: Install Node.js for web frontend
brew install node
```

#### 3. Setup Project Directory Structure
```bash
# Navigate to your Frigate project directory
cd /path/to/frigate-project

# Create /opt/frigate and copy project files
sudo mkdir -p /opt/frigate
sudo chown $(whoami):staff /opt/frigate

# Copy project to /opt/frigate
cp -r frigate /opt/frigate/
cp -r web /opt/frigate/
cp requirements.txt pyproject.toml /opt/frigate/

# Create directory structure (mirrors Docker layout)
cd /opt/frigate
mkdir -p {config,media,models,go2rtc,logs,db,tls,web-dist}
```

#### 4. Create Virtual Environment with uv
```bash
# Create virtual environment in /opt/frigate
cd /opt/frigate
uv venv --python 3.12 venv

# Activate virtual environment
source venv/bin/activate
```

#### 5. Install Python Dependencies

```bash
# Install main project dependencies
uv pip install -r requirements.txt

# Install additional macOS-specific packages
uv pip install \
    onnxruntime==1.20.* \
    transformers==4.45.* \
    google-generativeai==0.8.* \
    ollama==0.3.* \
    openai==1.65.* \
    py-vapid==1.9.* \
    pywebpush==2.0.* \
    pyclipper==1.3.* \
    shapely==2.0.* \
    Levenshtein==0.26.* \
    prometheus-client==0.21.*
```

#### 6. Download Models

Download required models to the models directory:
```bash
# Using recommended structure (/opt/frigate)
cd /opt/frigate/models

# OR using user directory structure
# cd ~/frigate-local/models

# Download CPU model for object detection
wget -O cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite

# Download labelmap (mirrors Docker rootfs/labelmap/)
wget -O labelmap.txt https://raw.githubusercontent.com/blakeblackshear/frigate/dev/labelmap.txt
wget -O coco.txt https://raw.githubusercontent.com/blakeblackshear/frigate/dev/docker/main/rootfs/labelmap/coco.txt

# Download audio model for audio detection
curl -L -o yamnet.tar.gz https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download
tar -xzf yamnet.tar.gz && mv 1.tflite cpu_audio_model.tflite && rm yamnet.tar.gz

# Download audio labelmap
wget -O audio-labelmap.txt https://raw.githubusercontent.com/blakeblackshear/frigate/dev/audio-labelmap.txt
```

#### 7. Install go2rtc (for WebRTC streaming)

```bash
# Download go2rtc to the go2rtc directory
cd /opt/frigate/go2rtc
# OR: cd ~/frigate-local/go2rtc

# Download go2rtc for macOS
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    GOARCH="arm64"
else
    GOARCH="amd64"
fi

curl -L -o go2rtc "https://github.com/AlexxIT/go2rtc/releases/download/v1.9.9/go2rtc_darwin_${GOARCH}"
chmod +x go2rtc

# Add to PATH
echo 'export PATH="/opt/frigate/go2rtc:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Configuration

#### 1. Create Directory Structure

Following the Docker s6 overlay service structure, create the recommended directory layout:

```bash
# Main application directory (mirrors Docker /opt/frigate)
sudo mkdir -p /opt/frigate
sudo chown $(whoami):staff /opt/frigate

# Configuration directory
mkdir -p /opt/frigate/config

# Media storage directory
mkdir -p /opt/frigate/media

# Models directory
mkdir -p /opt/frigate/models

# go2rtc directory
mkdir -p /opt/frigate/go2rtc

# Logs directory
mkdir -p /opt/frigate/logs

# Database directory
mkdir -p /opt/frigate/db

# TLS certificates directory (mirroring nginx setup)
mkdir -p /opt/frigate/tls

# Create symlinks for easier access
ln -s /opt/frigate ~/frigate
```

**Alternative User Directory Structure** (if you prefer user home directory):
```bash
mkdir -p ~/frigate-local/{config,media,models,go2rtc,logs,db,tls}
```

#### 2. Create Frigate Configuration

Create `/opt/frigate/config/config.yml` (or `~/frigate-local/config/config.yml` for user directory):

```yaml
# Database (mirrors Docker /config/frigate.db structure)
database:
  path: /opt/frigate/db/frigate.db

# Model configuration (mirrors Docker /opt/frigate structure)
model:
  path: /opt/frigate/models/cpu_model.tflite
  labelmap_path: /opt/frigate/models/labelmap.txt
  width: 320
  height: 320

# Detectors
detectors:
  cpu:
    type: cpu
    num_threads: 4

# Audio (optional)
audio:
  enabled: true
  max_not_heard: 30
  listen:
    - bark
    - fire_alarm
    - scream
    - speech
    - yell

# MQTT (optional - disable if not using Home Assistant)
mqtt:
  enabled: false
  # host: your-mqtt-broker
  # port: 1883
  # topic_prefix: frigate
  # client_id: frigate

# go2rtc configuration for WebRTC
go2rtc:
  streams:
    # Example RTSP camera
    # backyard: rtsp://username:password@camera-ip/stream1
    
  webrtc:
    candidates:
      - stun:8555

# Global ffmpeg configuration
ffmpeg:
  # Use system FFmpeg
  global_args: -hide_banner -loglevel warning
  hwaccel_args: [] # Add hardware acceleration if supported
  input_args: preset-rtsp-generic
  output_args:
    record: preset-record-generic-audio-copy

# Cameras configuration
cameras:
  # Example camera configuration
  # backyard:
  #   ffmpeg:
  #     inputs:
  #       - path: rtsp://username:password@camera-ip/stream1
  #         roles:
  #           - detect
  #           - record
  #       - path: rtsp://username:password@camera-ip/stream2
  #         roles:
  #           - record
  #   detect:
  #     width: 1280
  #     height: 720
  #     fps: 5
  #   record:
  #     enabled: true
  #     retain:
  #       days: 3
  #       mode: motion
  #   snapshots:
  #     enabled: true
  #     retain:
  #       default: 7

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
  improve_contrast: false

# Recording
record:
  enabled: true
  retain:
    days: 3
    mode: motion
  events:
    retain:
      default: 7
      mode: motion

# Snapshots
snapshots:
  enabled: true
  retain:
    default: 7

# Live view
live:
  height: 720
  quality: 8

# Version info
version: 0.16.0
```

Replace `{your-username}` with your actual macOS username.

## Running Frigate

### Using the Startup Script (Recommended)

The initialization script creates a complete startup script at `/opt/frigate/start-frigate.sh`:

```bash
# Start Frigate with all services
/opt/frigate/start-frigate.sh
```

**What it does**:
- Activates the uv virtual environment
- Sets all required environment variables
- Starts go2rtc in the background (port 1984)
- Starts Frigate FastAPI server (port 5001)
- Handles graceful shutdown with Ctrl+C

Frigate will be available at: **http://localhost:5001** (note different port from Docker)

### Manual Startup (Advanced)

If you need to start services manually:

#### 1. Activate Environment
```bash
cd /opt/frigate
source venv/bin/activate

# Set environment variables
export FRIGATE_CONFIG_FILE="/opt/frigate/config/config.yml"
export FRIGATE_MEDIA_DIR="/opt/frigate/media"
export DEFAULT_FFMPEG_VERSION="7.1"
export PATH="/opt/homebrew/bin:/opt/frigate/go2rtc:$PATH"
export PYTHONPATH="/opt/frigate:${PYTHONPATH:-}"

# Disable warnings
export TOKENIZERS_PARALLELISM=true
export TRANSFORMERS_NO_ADVISORY_WARNINGS=1
export OPENCV_FFMPEG_LOGLEVEL=8
```

#### 2. Start go2rtc (Terminal 1)
```bash
/opt/frigate/go2rtc/go2rtc -config /opt/frigate/config/go2rtc.yml
```

#### 3. Start Frigate (Terminal 2)
```bash
cd /opt/frigate
python -u -m frigate
```

## Updating Frigate

The local deployment makes updates simple:

```bash
# Navigate to your source project directory
cd /path/to/your/frigate-project

# Pull latest changes
git pull origin dev  # or main

# Re-run initialization to update /opt/frigate
./init-frigate.sh

# The script will detect existing installation and update accordingly
```

**What gets updated**:
- Python source code in `/opt/frigate/frigate/`
- Web frontend (if Node.js is available)
- Python dependencies (if requirements.txt changed)
- Configuration templates (preserves your existing config)

## Service Management (Optional)

### macOS LaunchAgent (Recommended)

Create a macOS LaunchAgent for automatic startup following s6 overlay service patterns.

**System-wide Service** (`/Library/LaunchDaemons/com.frigate.daemon.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.frigate.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/frigate/start-frigate.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/opt/frigate</string>
    <key>StandardOutPath</key>
    <string>/opt/frigate/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/opt/frigate/logs/launchd-stderr.log</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>YOUR_USERNAME</string>
</dict>
</plist>
```

**User Service** (`~/Library/LaunchAgents/com.frigate.agent.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.frigate.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USERNAME/frigate-local/start-frigate.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/YOUR_USERNAME/frigate-local</string>
    <key>StandardOutPath</key>
    <string>/Users/YOUR_USERNAME/frigate-local/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USERNAME/frigate-local/logs/launchd-stderr.log</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

**Load and manage the service**:
```bash
# Load user service
launchctl load ~/Library/LaunchAgents/com.frigate.agent.plist

# Start service
launchctl start com.frigate.agent

# Stop service
launchctl stop com.frigate.agent

# Unload service
launchctl unload ~/Library/LaunchAgents/com.frigate.agent.plist
```

## Troubleshooting

### Common Issues

1. **FFmpeg not found**: Ensure `/opt/homebrew/bin` is in your PATH
2. **Model loading errors**: Verify model files are downloaded and paths are correct
3. **Permission errors**: Ensure directories are writable by your user
4. **go2rtc connection issues**: Check that go2rtc is running and accessible on port 1984

### Hardware Acceleration

**VideoToolbox (Apple Silicon)**:
```yaml
ffmpeg:
  hwaccel_args: 
    - -hwaccel
    - videotoolbox
    - -hwaccel_output_format
    - videotoolbox_vld
```

**Docker vs Local Differences**:
- Docker: Uses custom FFmpeg build with hardware acceleration
- Local: Uses Homebrew FFmpeg with VideoToolbox support
- Performance may vary between implementations

### Performance Optimization

1. **Adjust detector threads**: Increase `num_threads` based on CPU cores
2. **Optimize detection resolution**: Lower detect resolution for better performance
3. **Use substreams**: Configure cameras with separate detect and record streams
4. **Limit FPS**: Set appropriate FPS values for detection vs recording

### Log Files

Following the s6 overlay service pattern, logs are organized in the logs directory:

**System-wide Installation**:
- Frigate logs: `/opt/frigate/logs/frigate.log`
- go2rtc logs: `/opt/frigate/logs/go2rtc.log`
- LaunchAgent logs: `/opt/frigate/logs/launchd-stdout.log`, `/opt/frigate/logs/launchd-stderr.log`

**User Directory Installation**:
- Frigate logs: `~/frigate-local/logs/frigate.log`
- go2rtc logs: `~/frigate-local/logs/go2rtc.log`

**Manual logging**:
```bash
# System-wide
/opt/frigate/start-frigate.sh 2>&1 | tee /opt/frigate/logs/manual.log

# User directory
~/frigate-local/start-frigate.sh 2>&1 | tee ~/frigate-local/logs/manual.log
```

**View live logs**:
```bash
# Frigate logs
tail -f /opt/frigate/logs/frigate.log

# go2rtc logs
tail -f /opt/frigate/logs/go2rtc.log
```

## Architecture Differences Summary

### Docker vs macOS Local

| Feature | Docker Version | macOS Local Version |
|---------|---------------|-------------------|
| **Port** | 8971 (nginx proxy) | 5001 (direct FastAPI) |
| **nginx** | ✅ Required (reverse proxy) | ❌ Not needed |
| **Python** | Container-managed | uv virtual environment |
| **FFmpeg** | Custom compiled | Homebrew FFmpeg 7.1+ |
| **go2rtc** | Bundled binary | Separate installation |
| **Updates** | `docker pull` | `git pull` + `./init-frigate.sh` |
| **Config** | Volume mounts | Direct file access |
| **Logs** | Docker logs | File-based logging |
| **Web UI** | Served via nginx | Direct from FastAPI |
| **Process Management** | s6-overlay | macOS launchd/manual |

### Key Benefits of Local Deployment

✅ **Direct FFmpeg control** - Use native macOS FFmpeg without version conflicts  
✅ **No Docker overhead** - Native performance without containerization  
✅ **Easy debugging** - Direct access to logs and configuration  
✅ **Simple updates** - Git pull and re-run script  
✅ **Development friendly** - Modify source code directly  

### Limitations

⚠️ **CPU-only inference** - No EdgeTPU or GPU acceleration  
⚠️ **Manual dependency management** - No automatic container updates  
⚠️ **Single platform** - macOS-specific (vs Docker multi-platform)  
⚠️ **No nginx benefits** - No built-in reverse proxy or caching

This approach gives you complete control over the Frigate deployment while avoiding Docker complexity and FFmpeg version conflicts.