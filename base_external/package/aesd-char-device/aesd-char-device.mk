
##############################################################
#
# AESD_CHAR_DEVICE
#
##############################################################

#TODO: Fill up the contents below in order to reference your assignment 3 git contents
AESD_CHAR_DEVICE_VERSION = '9d2a2677c2cb334cb3516128e707d4234d0f510f'
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
