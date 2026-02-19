SUMMARY = "JD9365DA-H3 panel kernel module"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://panel-jadard-jd9365da-h3.c file://Makefile"

S = "${WORKDIR}"

# Also install to a fixed path so the early systemd service can find it
do_install:append() {
    install -d ${D}/usr/lib/panel
    install -m 0644 ${S}/panel-jadard-jd9365da-h3.ko ${D}/usr/lib/panel/
}

FILES:${PN} += "/usr/lib/panel/panel-jadard-jd9365da-h3.ko"
