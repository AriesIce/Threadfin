# First stage. Building a binary
# -----------------------------------------------------------------------------
FROM golang:1.23-bullseye AS builder

WORKDIR /app

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code
COPY . .

# Build the application with optimizations
RUN CGO_ENABLED=0 go build -mod=mod -ldflags="-s -w" -trimpath -o threadfin threadfin.go

# Second stage. Creating a minimal image
# -----------------------------------------------------------------------------
FROM ubuntu:24.04

ARG BUILD_DATE
ARG VCS_REF
ARG THREADFIN_PORT=34400
ARG THREADFIN_VERSION
ARG TARGETARCH
ARG OS_VERSION=ubuntu
ARG OS_CODENAME=noble

LABEL org.label-schema.build-date="${BUILD_DATE}" \
      org.label-schema.name="Threadfin" \
      org.label-schema.description="Dockerized Threadfin" \
      org.label-schema.url="https://hub.docker.com/r/fyb3roptik/threadfin/" \
      org.label-schema.vcs-ref="${VCS_REF}" \
      org.label-schema.vcs-url="https://github.com/Threadfin/Threadfin" \
      org.label-schema.vendor="Threadfin" \
      org.label-schema.version="${THREADFIN_VERSION}" \
      org.label-schema.schema-version="1.0" \
      DISCORD_URL="https://discord.gg/bEPPNP2VG8"

ENV THREADFIN_BIN=/home/threadfin/bin \
    THREADFIN_CONF=/home/threadfin/conf \
    THREADFIN_HOME=/home/threadfin \
    THREADFIN_TEMP=/tmp/threadfin \
    THREADFIN_CACHE=/home/threadfin/cache \
    THREADFIN_UID=31337 \
    THREADFIN_GID=31337 \
    THREADFIN_USER=threadfin \
    THREADFIN_BRANCH=main \
    THREADFIN_DEBUG=0 \
    THREADFIN_PORT=34400 \
    THREADFIN_LOG=/var/log/threadfin.log \
    THREADFIN_BIND_IP_ADDRESS=0.0.0.0 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/threadfin/bin \
    DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR $THREADFIN_HOME

# Install dependencies in a single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    vlc \
    tzdata \
    gnupg \
    apt-transport-https && \
    mkdir -p $THREADFIN_BIN $THREADFIN_CONF $THREADFIN_TEMP $THREADFIN_HOME/cache && \
    chmod a+rwX $THREADFIN_CONF $THREADFIN_TEMP && \
    sed -i 's/geteuid/getppid/' /usr/bin/vlc && \
    curl -fsSL https://repo.jellyfin.org/master/ubuntu/jellyfin_team.gpg.key \

        | gpg --dearmor -o /etc/apt/trusted.gpg.d/ubuntu-jellyfin.gpg && \
    (if [ "${TARGETARCH}" = "arm" ]; then \
        echo "deb [arch=armhf] https://repo.jellyfin.org/master/${OS_VERSION} ${OS_CODENAME} main" > /etc/apt/sources.list.d/jellyfin.list; \
    else \
        echo "deb [arch=${TARGETARCH}] https://repo.jellyfin.org/master/${OS_VERSION} ${OS_CODENAME} main" > /etc/apt/sources.list.d/jellyfin.list; \
    fi) && \
    apt-get update && \
    apt-get install --no-install-recommends --no-install-suggests --yes \
        jellyfin-ffmpeg7 && \
    apt-get remove gnupg apt-transport-https --yes && \
    apt-get clean autoclean --yes && \
    apt-get autoremove --yes && \
    rm -rf /var/cache/apt/archives* /var/lib/apt/lists/*

# Copy built binary from builder image
COPY --from=builder /app/threadfin $THREADFIN_BIN/
RUN chmod +rx $THREADFIN_BIN/threadfin

# Create non-root user
RUN groupadd -g $THREADFIN_GID $THREADFIN_USER && \
    useradd -u $THREADFIN_UID -g $THREADFIN_USER -d $THREADFIN_HOME -s /bin/bash $THREADFIN_USER && \
    chown -R $THREADFIN_USER:$THREADFIN_USER $THREADFIN_HOME && \
    chown -R $THREADFIN_USER:$THREADFIN_USER $THREADFIN_TEMP && \
    chown $THREADFIN_USER:$THREADFIN_USER /var/log

# Configure container volume mappings
VOLUME $THREADFIN_CONF
VOLUME $THREADFIN_TEMP

EXPOSE $THREADFIN_PORT

# Switch to non-root user
USER $THREADFIN_USER

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$THREADFIN_PORT || exit 1

ENTRYPOINT ["sh", "-c", "exec ${THREADFIN_BIN}/threadfin -port=${THREADFIN_PORT} -bind=${THREADFIN_BIND_IP_ADDRESS} -config=${THREADFIN_CONF} -debug=${THREADFIN_DEBUG}"]
