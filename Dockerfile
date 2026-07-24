# Stage 1: Build
FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS builder
ARG TARGETARCH
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOARCH=$TARGETARCH go build -mod=mod -ldflags="-s -w" -trimpath -o threadfin threadfin.go

# Stage 2: Runtime (ARM64 optimized)
FROM alpine:3.19
LABEL maintainer="local-arm64-build"

ENV THREADFIN_BIN=/home/threadfin/bin \
    THREADFIN_CONF=/home/threadfin/conf \
    THREADFIN_TEMP=/tmp/threadfin \
    THREADFIN_PORT=34400 \
    THREADFIN_BIND_IP_ADDRESS=0.0.0.0 \
    THREADFIN_DEBUG=0 \
    TZ=Asia/Shanghai

RUN apk add --no-cache ca-certificates tzdata ffmpeg && \
    addgroup -S threadfin && adduser -S threadfin -G threadfin && \
    mkdir -p $THREADFIN_BIN $THREADFIN_CONF $THREADFIN_TEMP && \
    chown -R threadfin:threadfin /home/threadfin /tmp/threadfin

COPY --from=builder /app/threadfin $THREADFIN_BIN/
RUN chmod +x $THREADFIN_BIN/threadfin

USER threadfin
VOLUME [$THREADFIN_CONF, $THREADFIN_TEMP]
EXPOSE $THREADFIN_PORT

ENTRYPOINT ["sh", "-c", "${THREADFIN_BIN}/threadfin -port=${THREADFIN_PORT} -bind=${THREADFIN_BIND_IP_ADDRESS} -config=${THREADFIN_CONF} -debug=${THREADFIN_DEBUG}"]
