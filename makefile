#====================================================================================
# Oak makefile
#
# A slightly modified version of makeESPArduino, which
# is a makefile for ESP8286 Arduino projects.
#
# Base file available at
#    https://github.com/plerup/makeEspArduino
#
#====================================================================================

#====================================================================================
# User editable area
#====================================================================================

#=== Project specific definitions: sketch and list of needed libraries
SKETCH ?= $(shell find $(WORKSPACE_DIR) -name '*.ino')

# Esp8266 Arduino git location
ESP_ROOT ?= /oakCore
ESP_LIBS ?= /oakCore/libraries

LIBS ?= $(ESP_LIBS)/Wire \
        $(ESP_LIBS)/ESP8266WiFi \
        $(ESP_LIBS)/ESP8266mDNS \
        $(ESP_LIBS)/ESP8266WebServer

# Output directory
BUILD_ROOT ?= $(WORKSPACE_DIR)

# Board definitions
FLASH_SIZE ?= 32m
FLASH_MODE ?= qio
FLASH_SPEED ?= 40
FLASH_LAYOUT ?= oak_full.ld

# Upload parameters
UPLOAD_SPEED ?= 230400
UPLOAD_PORT ?= /dev/ttyUSB0
UPLOAD_VERB ?= -v

#====================================================================================
# The area below should normally not need to be edited
#====================================================================================

MKESPARD_VERSION = 1.0.0

START_TIME := $(shell perl -e "print time();")
# Main output definitions
MAIN_NAME = $(basename $(notdir $(SKETCH)))
MAIN_EXE = $(BUILD_ROOT)/$(MAIN_NAME).bin
MAIN_ELF = $(OBJ_DIR)/$(MAIN_NAME).elf

# esp8266 arduino directories
ESP_LIBS = $(ESP_ROOT)/libraries
TOOLS_ROOT = $(ESP_ROOT)/tools
TOOLS_BIN = $(TOOLS_ROOT)/xtensa-lx106-elf/bin
SDK_ROOT = $(ESP_ROOT)/tools/sdk

# Directory for intermedite build files
OBJ_DIR = $(BUILD_ROOT)/obj
OBJ_EXT = .o
DEP_EXT = .d

# Compiler definitions
CC = $(TOOLS_BIN)/xtensa-lx106-elf-gcc
CPP = $(TOOLS_BIN)/xtensa-lx106-elf-g++
LD =  $(CC)
AR = $(TOOLS_BIN)/xtensa-lx106-elf-ar
ESP_TOOL = $(TOOLS_ROOT)/0.9.1/esptool2

INCLUDE_DIRS += $(SDK_ROOT)/include $(CORE_DIR) $(ESP_ROOT)/variants/generic $(OBJ_DIR)
C_DEFINES = -D__ets__ -DICACHE_FLASH -U__STRICT_ANSI__ -DF_CPU=80000000L -DARDUINO=10605 -DARDUINO_ESP8266_ESP01 -DARDUINO_ARCH_ESP8266 -DESP8266
C_INCLUDES = $(foreach dir,$(INCLUDE_DIRS) $(USER_DIRS),-I$(dir))
C_FLAGS ?= -c -O2 -g -Wpointer-arith -Wno-implicit-function-declaration -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals -falign-functions=4 -MMD -std=gnu99 -ffunction-sections -fdata-sections
CPP_FLAGS ?= -c -O2 -g -mlongcalls -mtext-section-literals -fno-exceptions -fno-rtti -falign-functions=4 -std=c++11 -MMD -ffunction-sections -fdata-sections
S_FLAGS ?= -c -g -x assembler-with-cpp -MMD
LD_FLAGS ?= -g -O2 -nostdlib -Wl,--no-check-sections -u call_user_start -u Cache_Read_Enable_New -Wl,-static -L$(SDK_ROOT)/lib -L$(SDK_ROOT)/ld -T$(FLASH_LAYOUT) -Wl,--gc-sections -Wl,-wrap,system_restart_local -Wl,-wrap,register_chipv6_phy
LD_STD_LIBS ?= -lm -lgcc -lhal -lphy -lnet80211 -llwip -lwpa -lmain -lpp -lsmartconfig -lwps -lcrypto -laxtls

# Core source files
CORE_DIR = $(ESP_ROOT)/cores/oak
CORE_SRC = $(shell find $(CORE_DIR) -name "*.S" -o -name "*.c" -o -name "*.cpp")
CORE_OBJ = $(patsubst %,$(OBJ_DIR)/%$(OBJ_EXT),$(notdir $(CORE_SRC)))
CORE_LIB = $(OBJ_DIR)/core.ar

# User defined compilation units
USER_SRC = $(SKETCH) $(shell find $(LIBS) -name "*.S" -o -name "*.c" -o -name "*.cpp")
# Object file suffix seems to be significant for the linker...
USER_OBJ = $(subst .ino,.cpp,$(patsubst %,$(OBJ_DIR)/%$(OBJ_EXT),$(notdir $(USER_SRC))))
USER_DIRS = $(sort $(dir $(USER_SRC)))

VPATH += $(shell find $(CORE_DIR) -type d) $(USER_DIRS)

# Automatically generated build information data
# Makes the build date and git descriptions at the actual build
# event available as string constants in the program
BUILD_INFO_H = $(OBJ_DIR)/buildinfo.h
BUILD_INFO_CPP = $(OBJ_DIR)/buildinfo.cpp
BUILD_INFO_OBJ = $(BUILD_INFO_CPP)$(OBJ_EXT)

$(BUILD_INFO_H): | $(OBJ_DIR)
	echo "typedef struct { const char *date, *time, *src_version, *env_version;} _tBuildInfo; extern _tBuildInfo _BuildInfo;" >$@

# Utility functions
time_string = $(shell perl -e 'use POSIX qw(strftime); print strftime($(1), localtime());')
MEM_USAGE = \
  'while (<>) { \
      $$r += $$1 if /^\.(?:data|rodata|bss)\s+(\d+)/;\
		  $$f += $$1 if /^\.(?:irom0\.text|text|data|rodata)\s+(\d+)/;\
	 }\
	 print "\nMemory usage\n";\
	 print sprintf("  %-6s %6d bytes\n" x 2 ."\n", "Ram:", $$r, "Flash:", $$f);'

# Build rules
$(OBJ_DIR)/%.cpp$(OBJ_EXT): %.cpp $(BUILD_INFO_H)
	echo  $(<F)
	$(CPP) $(C_DEFINES) $(C_INCLUDES) $(CPP_FLAGS) $< -o $@

$(OBJ_DIR)/%.cpp$(OBJ_EXT): %.ino $(BUILD_INFO_H)
	echo  $(<F)
	$(CPP) -x c++ -include $(CORE_DIR)/Arduino.h $(C_DEFINES) $(C_INCLUDES) $(CPP_FLAGS) $< -o $@

$(OBJ_DIR)/%.c$(OBJ_EXT): %.c
	echo  $(<F)
	$(CC) $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) $< -o $@

$(OBJ_DIR)/%.S$(OBJ_EXT): %.S
	echo  $(<F)
	$(CC) $(C_DEFINES) $(C_INCLUDES) $(S_FLAGS) $< -o $@

$(CORE_LIB): $(CORE_OBJ)
	echo  Creating core archive
	rm -f $@
	$(AR) cru $@  $^

BUILD_DATE = $(call time_string,"%Y-%m-%d")
BUILD_TIME = $(call time_string,"%H:%M:%S")

build: $(CORE_LIB) $(USER_OBJ)
	echo Linking $(MAIN_EXE)
	echo '#include <buildinfo.h>' >$(BUILD_INFO_CPP)
	echo '_tBuildInfo _BuildInfo = {"$(BUILD_DATE)","$(BUILD_TIME)"};' >>$(BUILD_INFO_CPP)
	$(CPP) $(C_DEFINES) $(C_INCLUDES) $(CPP_FLAGS) $(BUILD_INFO_CPP) -o $(BUILD_INFO_OBJ)
	$(LD) $(LD_FLAGS) -Wl,--start-group $^ $(BUILD_INFO_OBJ) $(LD_STD_LIBS) -Wl,--end-group -L$(OBJ_DIR) -o $(MAIN_ELF)
	$(ESP_TOOL) -bin -boot2 -4096 -iromchksum $(MAIN_ELF) $(MAIN_EXE) .text .data .rodata
	$(TOOLS_BIN)/xtensa-lx106-elf-size -A $(MAIN_ELF) | perl -e $(MEM_USAGE)
	perl -e 'print "Build complete. Elapsed time: ", time()-$(START_TIME),  " seconds\n\n"'	

clean:
	echo Removing all intermediate build files...
	rm  -f $(OBJ_DIR)/*

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

.PHONY: all
all: $(OBJ_DIR) $(BUILD_INFO_H) $(CORE_LIB) $(USER_OBJ)


# Include all available dependencies
-include $(wildcard $(OBJ_DIR)/*$(DEP_EXT))

.DEFAULT_GOAL = all

ifndef VERBOSE
# Set silent mode as default
MAKEFLAGS += --silent
endif
