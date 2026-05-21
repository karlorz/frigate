# Frigate NVR - Tech Stack Design Summary

## Project Overview
Frigate is a complete and local Network Video Recorder (NVR) designed for Home Assistant with AI-powered real-time object detection for IP cameras. It emphasizes local processing, minimal resource usage, and maximum performance through intelligent motion detection and multiprocessing architecture.

## Core Architecture

### Backend (Python)
- **Framework**: FastAPI for REST API endpoints
- **Language**: Python 3.x with type hints and modern async/await patterns
- **Process Management**: Heavy use of multiprocessing for parallel video processing
- **Database**: SQLite with Peewee ORM for data persistence
- **Vector Database**: Custom SQLite extension (sqlite-vec) for embeddings storage
- **Configuration**: YAML-based configuration system
- **Logging**: Structured logging with configurable levels

### Frontend (React/TypeScript)
- **Framework**: React 18 with TypeScript
- **Build Tool**: Vite for fast development and optimized builds
- **UI Components**: Radix UI primitives for accessible, unstyled components
- **Styling**: Tailwind CSS with custom animations and scrollbar styling
- **State Management**: 
  - Recoil for global state
  - React Tracked for optimized re-renders
  - SWR for data fetching and caching
- **Routing**: React Router DOM v6
- **Forms**: React Hook Form with Zod validation
- **Charts**: ApexCharts for data visualization
- **Video**: Custom video players with HLS.js and JSMpeg support

### AI/ML Stack
- **Object Detection**: TensorFlow for real-time inference
- **Computer Vision**: OpenCV for image processing and motion detection
- **Hardware Acceleration**: 
  - Google Coral TPU support
  - Hailo AI accelerators
  - Intel OpenVINO
  - NVIDIA TensorRT
  - AMD ROCm
- **Models**: YOLO models with configurable detection parameters
- **Embeddings**: Vector embeddings for face recognition and similarity search

## Infrastructure & Deployment

### Containerization
- **Base**: Multi-stage Docker builds with Debian 12
- **Architecture Support**: Multi-platform (AMD64, ARM64)
- **Specialized Images**: 
  - Main deployment image
  - TensorRT-optimized builds
  - Raspberry Pi builds
  - Rockchip hardware builds
  - Hailo8L accelerator builds
- **Development**: DevContainer support for consistent dev environments

### Communication & Integration
- **MQTT**: Eclipse Mosquitto for Home Assistant integration
- **WebSockets**: Real-time communication for live updates
- **WebRTC/MSE**: Low-latency video streaming
- **RTSP**: Camera stream re-streaming to reduce connections
- **ZeroMQ**: Inter-process communication
- **Web Push**: Browser notifications

### Storage & Media
- **Video Storage**: Configurable retention policies
- **Recording**: 24/7 recording with event-based clips
- **Formats**: Support for various video codecs and containers
- **Thumbnails**: Automated thumbnail generation
- **Exports**: Video export functionality

## Development Tools & Quality

### Code Quality
- **Linting**: 
  - Python: Ruff for fast linting and formatting
  - TypeScript: ESLint with TypeScript rules
  - Prettier for consistent code formatting
- **Type Checking**: 
  - Python: MyPy for static type checking
  - TypeScript: Built-in TypeScript compiler
- **Testing**: 
  - Python: unittest framework
  - Frontend: Vitest with coverage reporting

### Build System
- **Python**: Standard Python packaging with pyproject.toml
- **Frontend**: Vite build system with TypeScript compilation
- **Docker**: Multi-stage builds with build optimization
- **Makefile**: Automated build and deployment scripts

### Documentation
- **Framework**: Docusaurus v3 for documentation site
- **API Docs**: OpenAPI documentation generation
- **Internationalization**: i18next for multi-language support
- **Deployment**: Netlify for documentation hosting

## Key Technical Features

### Performance Optimizations
- **Motion Detection**: Low-overhead motion detection to trigger object detection
- **Multiprocessing**: Separate processes for different video processing tasks
- **Frame Management**: Shared memory for efficient frame passing
- **Caching**: Multiple caching layers for improved performance
- **Hardware Acceleration**: Support for various AI accelerators

### Security & Configuration
- **Authentication**: JWT-based authentication system
- **Configuration**: Hot-reloadable YAML configuration
- **Environment**: Docker-based isolation
- **Secrets Management**: Secure handling of API keys and credentials

### Monitoring & Observability
- **Metrics**: Built-in performance and system metrics
- **Health Checks**: Container and service health monitoring
- **Logging**: Structured logging with configurable verbosity
- **Statistics**: Real-time processing statistics

## Integration Ecosystem
- **Home Assistant**: Native integration via custom component
- **MQTT Brokers**: Standard MQTT protocol support
- **IP Cameras**: Wide camera compatibility via RTSP/HTTP
- **Cloud Services**: Optional Frigate+ cloud integration
- **Mobile**: Progressive Web App capabilities

This architecture demonstrates a well-designed, scalable system that balances performance, maintainability, and extensibility while providing a rich user experience for video surveillance and AI-powered object detection.