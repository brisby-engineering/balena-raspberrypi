# Add JD9365DA-H3 overlay to boot partition (raspberrypi5 / CM5 only)
# 1) Add overlay to the list so overlay_dtbs_handler includes it in the boot partition
RPI_KERNEL_DEVICETREE_OVERLAYS:append:raspberrypi5 = " overlays/jd9365da-h3.dtbo"

# 2) Ensure overlay is deployed before boot partition is assembled.
#    Balena uses do_resin_boot_dirgen_and_deploy (not RPI_SDIMG), so we must depend here.
do_resin_boot_dirgen_and_deploy[depends] += "${@oe.utils.conditional('MACHINE','raspberrypi5',' jd9365da-overlay:do_deploy','',d)}"
