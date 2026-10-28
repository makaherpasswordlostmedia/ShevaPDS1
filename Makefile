TARGET = ImlacPDS1
OBJS = imlac_psp.o
CFLAGS = -O2 -G0 -Wall -std=gnu11
CXXFLAGS = $(CFLAGS) -fno-exceptions -fno-rtti
ASFLAGS = $(CFLAGS)
LIBS = -lpspgum -lpspgu -lpspge -lpspdisplay -lpspctrl -lpsppower -lm
EXTRA_TARGETS = EBOOT.PBP
PSP_EBOOT_TITLE = Imlac PDS-1
PSPSDK = $(shell psp-config --pspsdk-path)
include $(PSPSDK)/lib/build.mak
