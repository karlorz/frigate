# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Frigate is a complete and local NVR (Network Video Recorder) designed for Home Assistant with AI object detection. It uses OpenCV and TensorFlow to perform real-time object detection locally for IP cameras, with tight integration to Home Assistant via MQTT.

## Architecture

### Core Components

- **Backend (Python)**: Main Frigate application located in `/frigate/`
  - **API**: FastAPI-based REST API in `/frigate/api/`
  - **Object Detection**: TensorFlow-based detection with multiple detector plugins (`/frigate/detectors/`)
  - **Video Processing**: FFmpeg integration for camera streams and recording
  - **Database**: SQLite with vector search capabilities for embeddings
  - **Communication**: MQTT, WebSocket, and ZMQ for inter-process communication
  - **Services**: Multiprocessing architecture with specialized services (recording, detection, events)

- **Frontend (React/TypeScript)**: Modern web UI located in `/web/`
  - Built with Vite, React 18, TypeScript
  - Uses Tailwind CSS and Radix UI components
  - Real-time streaming with WebRTC/MSE support
  - Mobile-responsive design with PWA capabilities

- **Docker**: Multi-architecture container build system with specialized variants for different hardware
  - Main dockerfile: `/docker/main/Dockerfile`
  - Hardware-specific builds for NVIDIA TensorRT, AMD ROCm, Intel OpenVINO, ARM64, Rockchip, Hailo

### Key Subsystems

- **Motion Detection**: Low-overhead motion detection to trigger object detection
- **Object Tracking**: Centroid and Norfair-based object tracking
- **Recording System**: 24/7 recording with retention policies based on detected objects
- **Event Management**: Timeline-based event storage and review system
- **Embeddings**: ONNX-based face recognition and license plate recognition
- **PTZ Control**: Pan-tilt-zoom camera control with auto-tracking

## Development Commands

### Backend (Python)
- **Build local Docker image**: `make local`
- **Run tests**: `make run_tests` (runs unittest and mypy in Docker)
- **Run Frigate locally**: `make run` (requires config)
- **Linting**: Code uses Ruff for linting with config in `pyproject.toml`

### Frontend (Web)
Navigate to `/web/` directory first:
- **Development server**: `npm run dev` (runs on host 0.0.0.0)
- **Build**: `npm run build`
- **Lint**: `npm run lint` or `npm run lint:fix`
- **Format**: `npm run prettier:write`
- **Test**: `npm run test` (Vitest)
- **Coverage**: `npm run coverage`

### Documentation
Navigate to `/docs/` directory:
- **Install**: `npm i`
- **Development**: `npm run start`
- Built with Docusaurus 3.5

### Development Environment
- **Docker Compose**: Use `docker-compose.yml` for development with devcontainer
- **Development container**: Target `devcontainer` in main Dockerfile
- **MQTT**: Eclipse Mosquitto container included for testing

## Configuration

- **Main config**: `/config/config.yml` (see `/config/config.yml.example`)
- **Web config**: Environment variables and build-time configuration
- **Docker**: Hardware-specific group IDs required for GPU acceleration (render, video, plugdev groups)

## Database

- Uses SQLite with custom vector search extension (`sqlitevecq.py`)
- Migrations in `/migrations/` directory numbered sequentially
- Supports embeddings for face recognition and semantic search

## Testing

- **Python**: unittest framework with tests in `/frigate/test/`
- **Web**: Vitest with React Testing Library
- **API**: HTTP API tests using custom base test classes
- **Type checking**: MyPy for Python with config in `/frigate/mypy.ini`

## Key Dependencies

### Backend
- FastAPI for REST API
- OpenCV for computer vision
- TensorFlow/TensorFlow Lite for object detection
- Pydantic for configuration validation
- Peewee ORM for database operations

### Frontend
- React 18 with TypeScript
- Vite for build tooling
- Tailwind CSS + Radix UI for styling
- SWR for data fetching
- Recoil for state management
- Konva for canvas-based polygon editing

## Hardware Integration

Supports multiple AI accelerators:
- Google Coral Edge TPU
- NVIDIA TensorRT
- Intel OpenVINO
- AMD ROCm
- Hailo-8L
- RKNN (Rockchip)
- CPU fallback

## Multi-language Support

- Internationalization with i18next
- Translation files in `/web/public/locales/`
- Weblate integration for community translations