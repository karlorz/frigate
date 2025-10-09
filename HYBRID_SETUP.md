# Frigate Hybrid Setup Guide

This guide explains how to run Frigate in a hybrid configuration where:
- **go2rtc runs natively on macOS** (better performance, avoid Docker networking issues)
- **Frigate and nginx run in Docker containers** (maintain containerization benefits)

## Prerequisites

1. **go2rtc binary**: You should have go2rtc built at `/Users/karlchow/go2rtc/go2rtc`
2. **Docker and Docker Compose**: For running Frigate containers
3. **Python 3**: For configuration generation scripts
4. **Frigate dependencies**: Same as regular Frigate setup

## Architecture

```
Host (macOS)                    Docker Container
┌─────────────────────┐        ┌──────────────────────┐
│  go2rtc             │        │  Frigate             │
│  Port 1984 (API)    │◄───────┤  Port 5000 (Web)    │
│  Port 8554 (RTSP)   │        │                      │
│  Port 8555 (WebRTC) │        │  nginx               │
└─────────────────────┘        │  (proxies to host)   │
                               └──────────────────────┘
                                        │
                               ┌──────────────────────┐
                               │  MQTT                │
                               │  Port 1883           │
                               └──────────────────────┘
```

## Quick Start

1. **Build the hybrid Docker images**:
   ```bash
   ./scripts/frigate_hybrid.sh build
   ```

2. **Start the hybrid setup**:
   ```bash
   ./scripts/frigate_hybrid.sh start
   ```

3. **Check status**:
   ```bash
   ./scripts/frigate_hybrid.sh status
   ```

4. **View logs**:
   ```bash
   ./scripts/frigate_hybrid.sh logs
   ```

5. **Stop everything**:
   ```bash
   ./scripts/frigate_hybrid.sh stop
   ```

## Manual Setup Steps

### 1. Build Docker Images

```bash
docker-compose -f docker-compose.hybrid.yml build
```

### 2. Configure Frigate

Create your Frigate configuration at `config/config.yml` as usual. The go2rtc section will be automatically processed.

### 3. Start go2rtc on macOS

```bash
./scripts/start_go2rtc_macos.sh start
```

This will:
- Generate go2rtc configuration from your Frigate config
- Start go2rtc listening on localhost:1984

### 4. Start Frigate in Docker

```bash
docker-compose -f docker-compose.hybrid.yml up -d frigate-hybrid mqtt
```

## Configuration

### go2rtc Configuration

The go2rtc configuration is automatically generated from your Frigate config's `go2rtc` section. The generation script:
- Reads your `config/config.yml`
- Extracts the `go2rtc` section
- Adds necessary defaults (API CORS, WebRTC candidates, etc.)
- Saves to `config/go2rtc.yaml`

### Network Configuration

- **go2rtc API**: `http://localhost:1984`
- **Frigate Web**: `http://localhost:5000`
- **MQTT**: `localhost:1883`
- **RTSP**: `rtsp://localhost:8554/camera_name`
- **WebRTC**: Uses port 8555 (TCP/UDP)

### Docker Networking

The Docker containers use `host.docker.internal` to communicate with the host-based go2rtc service.

## Troubleshooting

### go2rtc Issues

1. **Check if go2rtc is running**:
   ```bash
   ./scripts/start_go2rtc_macos.sh status
   ```

2. **View go2rtc logs**:
   ```bash
   ./scripts/start_go2rtc_macos.sh logs
   ```

3. **Test go2rtc API**:
   ```bash
   curl http://localhost:1984/api/info
   ```

### Frigate Issues

1. **Check container status**:
   ```bash
   docker-compose -f docker-compose.hybrid.yml ps
   ```

2. **View Frigate logs**:
   ```bash
   docker-compose -f docker-compose.hybrid.yml logs -f frigate-hybrid
   ```

3. **Check connectivity to go2rtc**:
   ```bash
   docker-compose -f docker-compose.hybrid.yml exec frigate-hybrid curl http://host.docker.internal:1984/api/info
   ```

### Common Issues

1. **"Connection refused" to go2rtc**:
   - Ensure go2rtc is running on the host
   - Check that `host.docker.internal` resolves in the container
   - Verify no firewall is blocking the connection

2. **go2rtc config issues**:
   - Check your `config/config.yml` for syntax errors
   - Run the config generation script manually:
     ```bash
     python3 scripts/create_go2rtc_config_macos.py
     ```

3. **Docker build issues**:
   - Ensure you're using the correct Dockerfile:
     ```bash
     docker-compose -f docker-compose.hybrid.yml build --no-cache
     ```

## Development

For development work:

```bash
./scripts/frigate_hybrid.sh dev
```

This starts the development container instead of the production one.

## Files Created

- `docker/main/Dockerfile.hybrid` - Custom Dockerfile without go2rtc
- `docker/main/rootfs-hybrid/` - Modified rootfs without go2rtc services
- `docker-compose.hybrid.yml` - Docker Compose for hybrid setup
- `scripts/create_go2rtc_config_macos.py` - Config generation script
- `scripts/start_go2rtc_macos.sh` - go2rtc management script
- `scripts/frigate_hybrid.sh` - Master management script

## Benefits of Hybrid Setup

1. **Better go2rtc performance** on native macOS
2. **Avoid Docker networking complexity** for real-time streaming
3. **Easier debugging** of go2rtc issues
4. **Maintain containerization** for Frigate core application
5. **Flexible deployment** options

## Switching Back

To return to the full Docker setup, simply use the original `docker-compose.yml` and `docker/main/Dockerfile`.