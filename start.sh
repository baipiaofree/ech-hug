#!/bin/bash
set -e

# ---------------- config ----------------
APP_UID=${APP_UID:-1000}
APP_GID=${APP_GID:-1000}

WSPORT=${WSPORT:-7860}          # Caddy 对外端口
ECHPORT=$((WSPORT + 1))         # ECH 内部端口
export WSPORT ECHPORT

# ---------------- stage 1: root-only (DNS etc.) ----------------
if [ "$(id -u)" -eq 0 ]; then
  # 尽量修改 DNS 为 1.1.1.1 / 1.0.0.1（失败不退出）
  if [ -e /etc/resolv.conf ] && [ -w /etc/resolv.conf ]; then
    cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    {
      echo "nameserver 1.1.1.1"
      echo "nameserver 1.0.0.1"
    } > /etc/resolv.conf 2>/dev/null || {
      echo "WARN: DNS 強制設定失敗，已還原。" >&2
      mv /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
    }
  else
    echo "WARN: /etc/resolv.conf 不可寫或不存在，跳過 DNS 強制設定。" >&2
  fi

  # 切到普通用户继续执行第二阶段
  exec su-exec ${APP_UID}:${APP_GID} bash "$0"
fi

# ---------------- utils ----------------
cleanup() {
  kill ${ECH_PID:-} 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ---------------- stage 2: run as normal user ----------------

# 选择 ECH 下载地址
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|x64|amd64)
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    ;;
  i386|i686)
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-386"
    ;;
  armv8|arm64|aarch64)
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    ;;
  *)
    echo "不支持架构: $ARCH" >&2
    exit 1
    ;;
esac

# 下载 ECH（二进制静默）
curl -fsSL "$ECH_URL" -o /app/ech-server-linux
chmod +x /app/ech-server-linux

# 启动 ECH（后台静默）
ECH_ARGS=(/app/ech-server-linux -l "ws://0.0.0.0:$ECHPORT")
if [ -n "$TOKEN" ]; then
  ECH_ARGS+=(-token "$TOKEN")
fi

nohup "${ECH_ARGS[@]}" > /app/ech.log 2>&1 &
ECH_PID=$!

# 存活检查（失败才输出）
sleep 1
if ! kill -0 "$ECH_PID" 2>/dev/null; then
  echo "ERROR: ECH 启动失败" >&2
  tail -n 50 /app/ech.log >&2 || true
  exit 1
fi

# 前台启动 Caddy（占用 PID1）
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
