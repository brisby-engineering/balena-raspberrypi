SUMMARY = "Device tree overlay for JD9365DA-H3 panel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit deploy

SRC_URI = "file://jd9365da-h3-overlay.dts"
S = "${WORKDIR}"

do_compile() {
    dtc -@ -I dts -O dtb -o jd9365da-h3.dtbo jd9365da-h3-overlay.dts
}

do_deploy() {
    install -d ${DEPLOY_DIR_IMAGE}
    install -m 0644 ${S}/jd9365da-h3.dtbo ${DEPLOY_DIR_IMAGE}/jd9365da-h3.dtbo
}
addtask deploy after do_compile before do_build
