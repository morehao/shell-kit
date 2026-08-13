#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/mihomo"
DATA_DIR="${INSTALL_DIR}/data"
SUBSCRIPTION_URL=""

usage() {
    cat << EOF
Usage: $(basename "$0") -u <subscription_url>

Options:
    -u, --url      Subscription URL (required)
    -h, --help     Show this help message

Example:
    $(basename "$0") -u "https://your-subscription-url"

EOF
    exit 1
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed."
        echo "Please install Docker first: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! command -v docker compose &> /dev/null; then
        echo "Error: Docker Compose is not installed."
        echo "Please install Docker Compose first: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

create_directories() {
    echo "Creating directory structure..."
    mkdir -p "${DATA_DIR}"
}

download_subscription() {
    echo "Downloading subscription from ${SUBSCRIPTION_URL}..."

    local temp_file="${DATA_DIR}/proxies_temp.yaml"

    if ! curl -s -o "${temp_file}" "${SUBSCRIPTION_URL}"; then
        echo "Error: Failed to download subscription. Please check the URL."
        rm -f "${temp_file}"
        exit 1
    fi

    python3 << 'PYTHON_EOF'
import yaml
import sys

try:
    with open('/opt/mihomo/data/proxies_temp.yaml', 'r') as f:
        data = yaml.safe_load(f)

    output = {
        'proxies': data.get('proxies', []),
        'proxy-groups': data.get('proxy-groups', [])
    }

    with open('/opt/mihomo/data/proxies.yaml', 'w') as f:
        yaml.dump(output, f, allow_unicode=True, default_flow_style=False)

    print("Subscription processed successfully.")
except Exception as e:
    print(f"Error processing subscription: {e}")
    sys.exit(1)
PYTHON_EOF

    if [ $? -ne 0 ]; then
        echo "Error: Failed to process subscription data."
        rm -f "${temp_file}"
        exit 1
    fi

    rm -f "${temp_file}"
}

generate_docker_compose() {
    cat > "${INSTALL_DIR}/docker-compose.yml" << 'EOF'
services:
  mihomo:
    image: metacubex/mihomo:latest
    container_name: mihomo
    restart: unless-stopped
    volumes:
      - ./config.yaml:/root/.config/mihomo/config.yaml:ro
      - ./data:/root/.config/mihomo
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
    network_mode: host
    environment:
      - TZ=Asia/Shanghai
EOF
    echo "Generated docker-compose.yml"
}

generate_config() {
    cat > "${INSTALL_DIR}/config.yaml" << 'EOF'
mixed-port: 7890
allow-lan: false
bind-address: "127.0.0.1"
mode: rule
log-level: info
ipv6: true
external-controller: 127.0.0.1:9093

proxy-providers:
  mySub:
    type: file
    path: ./proxies.yaml
    health-check:
      enable: true
      interval: 600
      url: http://www.gstatic.com/generate_204

proxy-groups:
  - name: PROXY
    type: select
    use:
      - mySub

rules:
  - MATCH,PROXY
EOF
    echo "Generated config.yaml"
}

start_container() {
    echo "Starting Mihomo container..."
    cd "${INSTALL_DIR}"

    if ! docker compose up -d; then
        echo "Error: Failed to start container. Check logs with: docker compose logs"
        exit 1
    fi

    echo "Mihomo container started successfully."
}

show_verification() {
    echo ""
    echo "=========================================="
    echo "  Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Verify deployment with:"
    echo "  1. Check container status:"
    echo "     cd ${INSTALL_DIR} && docker compose ps"
    echo ""
    echo "  2. Check ports:"
    echo "     ss -tlnp | grep -E '7890|9093'"
    echo ""
    echo "  3. Test proxy:"
    echo "     curl -x http://127.0.0.1:7890 -s https://api.ip.sb/ip"
    echo ""
    echo "  4. View logs:"
    echo "     cd ${INSTALL_DIR} && docker compose logs -f"
    echo ""
}

parse_args() {
    if [ $# -eq 0 ]; then
        usage
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -u|--url)
                SUBSCRIPTION_URL="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [ -z "${SUBSCRIPTION_URL}" ]; then
        echo "Error: Subscription URL is required."
        usage
    fi
}

main() {
    parse_args "$@"

    echo "Starting Mihomo deployment..."
    echo ""

    check_docker
    create_directories
    download_subscription
    generate_docker_compose
    generate_config
    start_container
    show_verification
}

main "$@"
