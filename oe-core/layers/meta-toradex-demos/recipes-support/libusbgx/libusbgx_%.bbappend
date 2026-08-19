# When using the examples package, disable the usbgx service and instead
# call gadget-start from udev.
#
# The systemd target `usb-gadget.target` is triggered by udev when a UDC
# first comes up. The usbgx service uses this target and executes
# gadget-start to initialize the gadget. It can happen that by the time
# gadget-start runs, the UDC has been removed from the system again.
#
# Call gadget-start from udev every time a UDC comes up instead of only
# once via the systemd service (usbgx.service). Repeated runs of this
# script are not problematic.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://99-toradex-usb-udc.rules"

SYSTEMD_AUTO_ENABLE:${PN}-examples = "disable"

do_install:append() {
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/99-toradex-usb-udc.rules ${D}${sysconfdir}/udev/rules.d/
}
