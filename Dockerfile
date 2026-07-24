# Stage 1: Build
FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS builder

ARG TARGETARCH
WORKDIR /app

# ✅ 设置可信代理 + 禁用校验和数据库严格模式
# GOSUMDB=off 允许在 go.sum 缺失/不匹配时直接从 proxy 拉取并信任
ENV GOPROXY=https://proxy.golang.org,direct \
    GOSUMDB=off

COPY go.mod go.sum ./

# ✅ 强制重新同步依赖：忽略已有 go.sum，以 go.mod 为准重新生成
# 这替代了本地 rm go.sum && go mod tidy 的操作
RUN go mod tidy

COPY . .

RUN CGO_ENABLED=0 GOARCH=$TARGETARCH go build \
    -mod=mod \
    -ldflags="-s -w" \
    -trimpath \
    -o threadfin threadfin.go

# Stage 2: Runtime (ARM64 optimized)
FROM alpine:3.19

LABEL maintainer="local-arm64-build"

# 安装运行时依赖
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    ffmpeg \
    vlc

# 创建非 root 用户
RUN addgroup -g 1000 threadfin && \
    adduser -D -u 1000 -G threadfin threadfin

# 设置环境变量
ENV THREADFIN_BIN=/home/threadfin/bin \
    THREADFIN_HOME=/home/threadfin/data \
    THREADFIN_PORT=34400

# 创建工作目录
RUN mkdir -p /home/threadfin/bin \
             /home/threadfin/data \
             /home/threadfin/logs && \
    chown -R threadfin:threadfin /home/threadfin

# 从构建阶段复制二进制文件
COPY --from=builder --chown=threadfin:threadfin /app/threadfin /home/threadfin/bin/threadfin

# 复制配置文件（如果有的话）
COPY --from=builder --chown=threadfin:threadfin /app/html /home/threadfin/bin/html
COPY --from=builder --chown=threadfin:threadfin /app/templates /home/threadfin/bin/templates

# 暴露端口
EXPOSE 34400

# 切换到非 root 用户
USER threadfin

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:34400 || exit 1

# 设置工作目录
WORKDIR /home/threadfin/bin

# 启动命令
ENTRYPOINT ["./threadfin"]
