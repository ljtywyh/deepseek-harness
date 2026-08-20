# syntax=docker/dockerfile:1.7
#
# DeepSeek Harness (dsh) — 生产镜像（方案 1：Docker + 端口映射浏览器访问）
# 构建上下文：仓库根目录。
#
# 重要安全说明：
#   dsh web 出于安全考虑【刻意拒绝】绑定 0.0.0.0（源码注释：会将对网络的
#   远程代码执行暴露出去）。因此本镜像让 harness 监听 127.0.0.1:3080，
#   再用 nginx 反代 + Basic Auth 对外暴露 0.0.0.0:8080。
#   => 必须设置 DSH_WEB_PASSWORD（见 entrypoint.sh / docker-compose.yml），
#      否则将生成随机密码并打印到日志。切勿在未加认证的情况下把 8080 映射到公网。

# ===================== Stage 1: build =====================
FROM node:22.19.0-bookworm AS build
ENV CI=true \
    PYTHON=/usr/bin/python3 \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH

# pnpm 版本与仓库 package.json 的 packageManager 一致（pnpm@11.7.0）
RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

# 原生模块（node-pty / koffi）编译所需的工具链；landlock-run 为预编译二进制，无需 Rust。
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential python3 git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 复制源码（.dockerignore 已排除 node_modules / .git / 构建产物，保证从零构建）
COPY . .

# 安装依赖（pnpm 11 的 allowBuilds 已放行 esbuild/lefthook/node-pty/koffi/dsh-subprocess-local）
RUN pnpm install --prefer-frozen-lockfile
# 构建全部产物（host / client / web 前端等）
RUN pnpm run build

# ===================== Stage 2: runtime =====================
FROM node:22.19.0-bookworm-slim AS runtime
ENV NODE_ENV=production \
    HOME=/data \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH

# nginx：认证反代；curl：健康检查；apache2-utils：htpasswd 生成密码
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx curl apache2-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default \
 && corepack enable && corepack prepare pnpm@11.7.0 --activate

# 复制完整构建产物（含 node_modules 与 lib/dist）。如要瘦身可改为 pnpm deploy / --prod。
COPY --from=build /app /app

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && useradd -m -u 1000 app \
 && mkdir -p /data /tmp/nginx-temp \
 && chown -R app:app /data /tmp/nginx-temp

WORKDIR /app
USER app

# 对外暴露的是 nginx 反代端口（已加 Basic Auth），不是 harness 直连端口。
EXPOSE 8080

# 健康检查直连 harness 后端（绕过反代鉴权，仅本机探测）
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3080/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["web"]
