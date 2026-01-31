# Out-of-tree kernel module; module.bbclass passes KERNEL_PATH, O, CC, etc.
obj-m += panel-jadard-jd9365da-h3.o

all:
	$(MAKE) -C $(KERNEL_PATH) M=$(CURDIR) O=$(O) modules

clean:
	$(MAKE) -C $(KERNEL_PATH) M=$(CURDIR) O=$(O) clean
