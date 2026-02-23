SUMMARY = "Panel driver diagnostic script for JD9365DA-H3"
DESCRIPTION = "Run on device to check if panel driver is present, loaded, overlay, device tree, and which variant (NEW mipi_dsi_multi vs OLD legacy)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://check-panel-on-device.sh"
S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/check-panel-on-device.sh ${D}${bindir}/
}

FILES:${PN} = "${bindir}/check-panel-on-device.sh"
