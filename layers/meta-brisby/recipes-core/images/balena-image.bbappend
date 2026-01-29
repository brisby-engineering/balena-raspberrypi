# Add JD9365DA-H3 overlay to boot partition and depend on overlay deploy (raspberrypi5 / CM5 only)
RPI_KERNEL_DEVICETREE_OVERLAYS:append:raspberrypi5 = " overlays/jd9365da-h3.dtbo"
RPI_SDIMG_EXTRA_DEPENDS:append:raspberrypi5 = " jd9365da-overlay:do_deploy"
