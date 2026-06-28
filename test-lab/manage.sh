#!/usr/bin/env bash
# 管理 TermiScope Docker 测试主机集群
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

DOCKER="${DOCKER:-docker}"
if ! $DOCKER info &>/dev/null; then
  if sudo -n docker info &>/dev/null 2>&1; then
    DOCKER="sudo docker"
  elif [[ -t 0 ]]; then
    DOCKER="sudo docker"
  else
    echo "无法访问 Docker，请执行: sudo usermod -aG docker \$USER && newgrp docker"
    echo "或: sudo bash $0 $*"
    exit 1
  fi
fi

COMPOSE="$DOCKER compose"

cmd="${1:-info}"
shift || true

case "$cmd" in
  up|start)
    echo "==> 构建并启动测试主机..."
    $COMPOSE up -d --build
    echo "==> 等待 SSH 就绪..."
    for port in 2201 2202 2203; do
      for _ in $(seq 1 30); do
        if (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
          break
        fi
        sleep 1
      done
    done
    bash "$DIR/manage.sh" info
    ;;
  down|stop)
    $COMPOSE down
    ;;
  restart)
    $COMPOSE down
    $COMPOSE up -d --build
    bash "$DIR/manage.sh" info
    ;;
  status|ps)
    $COMPOSE ps
    ;;
  info)
    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    cat <<EOF

TermiScope 测试主机集群
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  账号: root / testuser    密码: testpass

  主机          容器 IP         SSH (本机)              用途
  ─────────────────────────────────────────────────────────────
  test-host1    172.30.10.11    127.0.0.1:2201          Debian + systemd
  test-host2    172.30.10.12    127.0.0.1:2202          Debian + systemd
  test-host3    172.30.10.13    127.0.0.1:2203          Debian + systemd

  在 TermiScope「主机管理」中添加示例:
    地址: 127.0.0.1   端口: 2201   用户: root   密码: testpass

  部署 Agent 时，请用局域网 IP 访问 TermiScope（容器内可回连）:
    http://${HOST_IP:-<你的IP>}:8080

  容器内验证回连: docker exec termiscope-test-host1 curl -s http://host.docker.internal:8080
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    ;;
  ssh)
    target="${1:-1}"
    case "$target" in
      1|host1|test-host1) port=2201 ;;
      2|host2|test-host2) port=2202 ;;
      3|host3|test-host3) port=2203 ;;
      *) echo "用法: $0 ssh [1|2|3]"; exit 1 ;;
    esac
    exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$port" root@127.0.0.1
    ;;
  logs)
    $COMPOSE logs -f "${1:-}"
    ;;
  *)
    echo "用法: $0 {up|down|restart|status|info|ssh [1-3]|logs [service]}"
    exit 1
    ;;
esac
