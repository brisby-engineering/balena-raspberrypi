SUMMARY = "Hold Balena update lock to prevent host OS overwrite"
DESCRIPTION = "Runs at boot and holds /tmp/balena/updates.lock so the supervisor cannot apply host OS updates. Use when running a custom-flashed image in a fleet that has a different target OS."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://prevent-host-os-update.sh file://prevent-host-os-update.service"
S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "prevent-host-os-update.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${libexecdir}
    install -m 0755 ${S}/prevent-host-os-update.sh ${D}${libexecdir}/
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/prevent-host-os-update.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${libexecdir}/prevent-host-os-update.sh ${systemd_system_unitdir}/prevent-host-os-update.service"
