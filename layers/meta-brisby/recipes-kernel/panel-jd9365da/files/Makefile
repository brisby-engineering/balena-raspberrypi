# Out-of-tree kernel module; module.bbclass passes KERNEL_SRC/KERNEL_PATH, O, CC, etc.
# do_configure runs "make clean" with KERNEL_SRC only; do_compile passes KERNEL_PATH and O.
KERNEL_DIR ?= $(or $(KERNEL_PATH),$(KERNEL_SRC))
obj-m += panel-jadard-jd9365da-h3.o

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(CURDIR) $(if $(O),O=$(O)) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(CURDIR) $(if $(O),O=$(O)) clean
