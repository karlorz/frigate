#!/bin/bash
# Master script for Frigate hybrid setup (go2rtc on macOS + Frigate in Docker)

set -e

FRIGATE_ROOT="/Users/karlchow/Desktop/code/frigate-local"
GO2RTC_SCRIPT="${FRIGATE_ROOT}/scripts/start_go2rtc_macos.sh"
DOCKER_COMPOSE_FILE="${FRIGATE_ROOT}/docker-compose.hybrid.yml"

cd "$FRIGATE_ROOT"

# Function to start the hybrid setup
start_hybrid() {
    echo "[INFO] Starting Frigate hybrid setup..."
    echo "[INFO] 1. Starting go2rtc on macOS..."
    
    # Start go2rtc
    "$GO2RTC_SCRIPT" start
    
    echo "[INFO] 2. Starting Frigate and nginx in Docker..."
    
    # Start Docker containers
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d frigate-hybrid mqtt
    
    echo "[INFO] Hybrid setup started successfully!"
    echo ""
    echo "Services:"
    echo "  - go2rtc (macOS):     http://localhost:1984"
    echo "  - Frigate (Docker):   http://localhost:5000"
    echo "  - MQTT (Docker):      localhost:1883"
    echo ""
    echo "To view logs:"
    echo "  - go2rtc:    $GO2RTC_SCRIPT logs"
    echo "  - Frigate:   docker-compose -f $DOCKER_COMPOSE_FILE logs -f frigate-hybrid"
    echo ""
    echo "To stop: $0 stop"
}

# Function to stop the hybrid setup
stop_hybrid() {
    echo "[INFO] Stopping Frigate hybrid setup..."
    
    echo "[INFO] 1. Stopping Docker containers..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" down
    
    echo "[INFO] 2. Stopping go2rtc..."
    "$GO2RTC_SCRIPT" stop
    
    echo "[INFO] Hybrid setup stopped successfully!"
}

# Function to restart the hybrid setup
restart_hybrid() {
    echo "[INFO] Restarting Frigate hybrid setup..."
    stop_hybrid
    sleep 2
    start_hybrid
}

# Function to show status
status_hybrid() {
    echo "[INFO] Frigate hybrid setup status:"
    echo ""
    
    echo "=== go2rtc (macOS) ==="
    "$GO2RTC_SCRIPT" status
    echo ""
    
    echo "=== Docker containers ==="
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps
}

# Function to show logs
logs_hybrid() {
    local service="${1:-all}"
    
    case "$service" in
        go2rtc)
            "$GO2RTC_SCRIPT" logs
            ;;
        frigate)
            docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f frigate-hybrid
            ;;
        mqtt)
            docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f mqtt
            ;;
        all)
            echo "[INFO] Starting log viewer for all services..."
            echo "[INFO] Press Ctrl+C to exit"
            echo ""
            docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f &
            "$GO2RTC_SCRIPT" logs
            ;;
        *)
            echo "[ERROR] Unknown service: $service"
            echo "Available services: go2rtc, frigate, mqtt, all"
            exit 1
            ;;
    esac
}

# Function to build Docker images
build_hybrid() {
    echo "[INFO] Building Docker images for hybrid setup..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" build
}

# Main execution
case "${1:-help}" in
    start)
        start_hybrid
        ;;
    stop)
        stop_hybrid
        ;;
    restart)
        restart_hybrid
        ;;
    status)
        status_hybrid
        ;;
    logs)
        logs_hybrid "${2:-all}"
        ;;
    build)
        build_hybrid
        ;;
    dev)
        echo "[INFO] Starting development setup..."
        "$GO2RTC_SCRIPT" start
        docker-compose -f "$DOCKER_COMPOSE_FILE" --profile dev up -d
        echo "[INFO] Development setup ready"
        ;;
    help|*)
        echo "Frigate Hybrid Setup Manager"
        echo "Usage: $0 {start|stop|restart|status|logs|build|dev}"
        echo ""
        echo "Commands:"
        echo "  start     - Start the hybrid setup (go2rtc + Frigate)"
        echo "  stop      - Stop the hybrid setup"
        echo "  restart   - Restart the hybrid setup"
        echo "  status    - Show status of all services"
        echo "  logs      - Show logs (options: go2rtc, frigate, mqtt, all)"
        echo "  build     - Build Docker images"
        echo "  dev       - Start development environment"
        echo "  help      - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Start everything"
        echo "  $0 logs frigate            # View Frigate logs only"
        echo "  $0 logs go2rtc             # View go2rtc logs only"
        exit 1
        ;;
esac