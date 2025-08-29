#!/bin/bash

# Cutover script for switching from MSK to Confluent Cloud

set -e

CONSUMER_PID_FILE="consumer.pid"
PRODUCER_PID_FILE="producer.pid"
LOG_DIR="logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

stop_process() {
    local pid_file=$1
    local process_name=$2
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            log "Stopping $process_name (PID: $pid)..."
            kill -SIGTERM $pid
            
            # Wait for graceful shutdown
            local count=0
            while kill -0 $pid 2>/dev/null && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            # Force kill if still running
            if kill -0 $pid 2>/dev/null; then
                warning "Force killing $process_name..."
                kill -SIGKILL $pid
            fi
            
            success "$process_name stopped"
        fi
        rm -f "$pid_file"
    else
        warning "$process_name PID file not found, process may not be running"
    fi
}

start_consumer() {
    local env_file=$1
    log "Starting consumer with environment: $env_file"
    
    source "$env_file"
    nohup python3 orders_consumer.py > "$LOG_DIR/consumer.log" 2>&1 &
    echo $! > "$CONSUMER_PID_FILE"
    
    success "Consumer started (PID: $(cat $CONSUMER_PID_FILE))"
}

start_producer() {
    local env_file=$1
    log "Starting producer with environment: $env_file"
    
    source "$env_file"
    nohup python3 orders_producer.py > "$LOG_DIR/producer.log" 2>&1 &
    echo $! > "$PRODUCER_PID_FILE"
    
    success "Producer started (PID: $(cat $PRODUCER_PID_FILE))"
}

cutover() {
    local target_env=$1
    local env_file="env.$target_env"
    
    if [ ! -f "$env_file" ]; then
        error "Environment file $env_file not found!"
        exit 1
    fi
    
    log "🔄 Starting cutover to $target_env..."
    
    # Stop existing processes
    log "Stopping existing processes..."
    stop_process "$CONSUMER_PID_FILE" "Consumer"
    stop_process "$PRODUCER_PID_FILE" "Producer"
    
    # Brief pause to ensure clean shutdown
    sleep 2
    
    # Create topic in new environment (if needed)
    log "Creating topic in new environment..."
    source "$env_file"
    python3 create_topic.py orders || warning "Topic creation failed or topic already exists"
    
    # Start processes with new environment
    log "Starting processes with new environment..."
    start_consumer "$env_file"
    sleep 2
    start_producer "$env_file"
    
    success "🎉 Cutover to $target_env completed successfully!"
    log "Check logs in $LOG_DIR/ for process output"
}

status() {
    log "Process Status:"
    echo "=================="
    
    if [ -f "$CONSUMER_PID_FILE" ]; then
        local consumer_pid=$(cat "$CONSUMER_PID_FILE")
        if kill -0 $consumer_pid 2>/dev/null; then
            success "Consumer: Running (PID: $consumer_pid)"
        else
            error "Consumer: Not running (stale PID file)"
        fi
    else
        warning "Consumer: No PID file found"
    fi
    
    if [ -f "$PRODUCER_PID_FILE" ]; then
        local producer_pid=$(cat "$PRODUCER_PID_FILE")
        if kill -0 $producer_pid 2>/dev/null; then
            success "Producer: Running (PID: $producer_pid)"
        else
            error "Producer: Not running (stale PID file)"
        fi
    else
        warning "Producer: No PID file found"
    fi
    
    echo ""
    log "Current environment: ${KAFKA_ENV:-"Not set"}"
}

usage() {
    echo "Usage: $0 {cutover|status|stop}"
    echo ""
    echo "Commands:"
    echo "  cutover <env>  - Switch to specified environment (msk, msk-scram, cc)"
    echo "  status         - Show current process status"
    echo "  stop           - Stop all processes"
    echo ""
    echo "Examples:"
    echo "  $0 cutover cc      # Switch to Confluent Cloud"
    echo "  $0 cutover msk     # Switch back to MSK"
    echo "  $0 status          # Check process status"
    echo "  $0 stop            # Stop all processes"
}

# Main script logic
case "$1" in
    cutover)
        if [ -z "$2" ]; then
            error "Environment required for cutover!"
            usage
            exit 1
        fi
        
        if [[ "$2" != "msk" && "$2" != "msk-scram" && "$2" != "cc" ]]; then
            error "Invalid environment: $2"
            error "Valid environments: msk, msk-scram, cc"
            exit 1
        fi
        
        cutover "$2"
        ;;
    status)
        status
        ;;
    stop)
        log "Stopping all processes..."
        stop_process "$CONSUMER_PID_FILE" "Consumer"
        stop_process "$PRODUCER_PID_FILE" "Producer"
        success "All processes stopped"
        ;;
    *)
        usage
        exit 1
        ;;
esac 