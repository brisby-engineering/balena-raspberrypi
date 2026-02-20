SUMMARY = "JD9365DA-H3 panel kernel module (legacy DSI API, TXW990002B0/cw,txw990002b0)"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

PR = "r1"

inherit module

SRC_URI = "file://panel-jadard-jd9365da-h3.c file://Makefile"

S = "${WORKDIR}"

# Service uses modprobe, which loads from /lib/modules/.../updates/ (kernel-module-* package).
# Do NOT install a second copy to /usr/lib/panel so the image has a single source of truth.
