#!/bin/bash
# dsh 容器入口：先起带 Basic Auth 的 nginx 反代（0.0.0.0:8080 -> 127.0.0.1:3080），
# 再以 exec 前台运行 harness（127.0.0.1:3080，--no-open 不弹浏览器）。
set -euo pipefail

USER_NAME="${DSH_WEB_USER:-admin}"

# 未设置密码则生成随机密码并打印一次（仅供本地/内网使用，公网务必显式设置）。
if [ -z "${DSH_WEB_PASSWORD:-}" ]; then
  DSH_WEB_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
  echo "==================================================================="
  echo "  DSH_WEB_PASSWORD 未设置，已生成随机密码："
  echo "  用户名: ${USER_NAME}    密码: ${DSH_WEB_PASSWORD}"
  echo "  请在 docker run -e DSH_WEB_PASSWORD=xxx 中显式设置后再对外暴露。"
  echo "==================================================================="
fi

htpasswd -b -c /tmp/dsh.htpasswd "$USER_NAME" "$DSH_WEB_PASSWORD"

# 反代指向 harness 本地端口（与 nginx.conf 保持一致）
export DSH_BACKEND_PORT="${DSH_BACKEND_PORT:-3080}"
nginx -c /etc/nginx/nginx.conf

# 前台运行 harness；profile=web，仅监听本机，不自动打开浏览器。
# harness 拒绝 --host 0.0.0.0，故固定 127.0.0.1。
exec pnpm dsh web --no-open --host 127.0.0.1 --port "${DSH_BACKEND_PORT}"
