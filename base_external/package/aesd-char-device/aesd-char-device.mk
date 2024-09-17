
##############################################################
#
# AESD_CHAR_DEVICE
#
##############################################################

#TODO: Fill up the contents below in order to reference your assignment 3 git contents
AESD_CHAR_DEVICE_VERSION = '8ff6a910661658eecec9c98ca8eb4c4ed0903dea'
# Note: Be sure to reference the *ssh* repository URL here (not https) to work properly
# with ssh keys and the automated build/test system.
# Your site should start with git@github.com:
AESD_CHAR_DEVICE_SITE = 'git@github.com:cu-ecen-aeld/assignments-3-and-later-tasifacuj.git'
AESD_CHAR_DEVICE_SITE_METHOD = git
AESD_CHAR_DEVICE_GIT_SUBMODULES = YES

AESD_CHAR_DEVICE_MODULE_SUBDIRS = aesd-char-driver
AESD_CHAR_DEVICE_MODULE_MAKE_OPTS = KERNELDIR=$(LINUX_DIR)

$(eval $(kernel-module))

define AESD_CHAR_DEVICE_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 $(@D)/aesd-char-driver/aesdchar_load $(TARGET_DIR)/usr/bin/
	$(INSTALL) -m 0755 $(@D)/aesd-char-driver/aesdchar_unload $(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))
