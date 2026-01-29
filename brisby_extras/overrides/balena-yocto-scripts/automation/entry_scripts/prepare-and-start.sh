#!/bin/bash
set -e

VERBOSE=${VERBOSE:-0}
[ "${VERBOSE}" = "verbose" ] && set -x

source /balena-docker.inc

trap 'balena_docker_stop fail' SIGINT SIGTERM

INSTALL_DIR="/work"

# Create the normal user to be used for bitbake (barys)
echo "[INFO] Creating and setting builder user $BUILDER_UID:$BUILDER_GID."
# GID may already exist in container (e.g. 0=root, 20=dialout on Ubuntu; host macOS often uses 20=staff)
if [ "$BUILDER_GID" != "0" ]; then
  getent group "$BUILDER_GID" >/dev/null 2>&1 || groupadd -g "$BUILDER_GID" builder
fi
if ! cat "/etc/group" | grep docker > /dev/null; then  groupadd docker; fi
# UID 0 = root already exists; only create builder when non-root
if [ "$BUILDER_UID" != "0" ]; then
  useradd -m -u $BUILDER_UID -g $BUILDER_GID -G docker builder && newgrp docker
  RUN_AS_USER="builder"
else
  gpasswd -a root docker 2>/dev/null || true
  RUN_AS_USER="root"
fi

# Make the "builder" user inherit the $SSH_AUTH_SOCK variable set-up so he can use the host ssh keys for various operations
# (like being able to clone private git repos from within bitbake using the ssh protocol)
echo 'Defaults env_keep += "SSH_AUTH_SOCK"' > /etc/sudoers.d/ssh-auth-sock

# Disable host authenticity check when accessing git repos using the ssh protocol
# (not disabling it will make this script fail because known_hosts is empty)
BUILDER_HOME=$(getent passwd "$RUN_AS_USER" | cut -d: -f6)
mkdir -p "$BUILDER_HOME/.ssh/"
echo "StrictHostKeyChecking no" > "$BUILDER_HOME/.ssh/config"

# Start docker
balena_docker_start
balena_docker_wait

sudo -H -u "$RUN_AS_USER" git config --global user.name "Resin Builder"
sudo -H -u "$RUN_AS_USER" git config --global user.email "buildy@builder.com"
echo "[INFO] The configured git credentials for user $RUN_AS_USER are:"
sudo -H -u "$RUN_AS_USER" git config --get user.name
sudo -H -u "$RUN_AS_USER" git config --get user.email

# Start barys with all the arguments requested
echo "[INFO] Running build as $RUN_AS_USER user..."
if [ -d "${INSTALL_DIR}/balena-yocto-scripts" ]; then
    sudo -H -u "$RUN_AS_USER" "${INSTALL_DIR}/balena-yocto-scripts/build/barys" $@ &
else
    sudo -H -u "$RUN_AS_USER" "${INSTALL_DIR}/resin-yocto-scripts/build/barys" $@ &
fi
barys_pid=$!
wait $barys_pid || true

balena_docker_stop
exit 0
