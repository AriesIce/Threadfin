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

ENV THREADFIN_BIN=/home/threadfin/bin \
    TH
