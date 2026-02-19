#!/bin/sh
# Hold the Balena update lock so the supervisor cannot apply host OS updates.
# This keeps a custom-flashed image from being overwritten by the fleet's target OS.
mkdir -p /tmp/balena
exec flock -x /tmp/balena/updates.lock sleep infinity
