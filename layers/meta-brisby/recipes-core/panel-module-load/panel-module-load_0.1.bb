SUMMARY = "Systemd service to load JD9365DA-H3 panel module at boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://panel-module-load.service"
S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "panel-module-load.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/panel-module-load.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${systemd_system_unitdir}/panel-module-load.service"

# Recipe panel-jd9365da-h3 installs .ko to /usr/lib/panel
RDEPENDS:${PN} = "panel-jd9365da-h3"
