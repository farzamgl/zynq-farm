# Allocate benchmarks to boards in Makefile.frag
include Makefile.frag

SHELL := /bin/bash

# Set this to your name
NAME        ?= joe

# Work branch and example
URL         ?= git@github.com:black-parrot-hdk/zynq-parrot.git
BRANCH      ?= master
EXAMPLE     ?= black-parrot-example

# Board and Vivado info
BOARDNAME      = ultra96v2
VIVADO_VERSION = 2020.1
VIVADO_MODE    = batch
FPGA_ARGS      = BOARDNAME=$(BOARDNAME) VIVADO_VERSION=$(VIVADO_VERSION) VIVADO_MODE=$(VIVADO_MODE)

# Server and client NFS mounts
SERVER_MNT   = $(CURDIR)
BOARD_MNT    = /home/xilinx/$(NAME)/mnt/nfs_client
BITSTREAM    = blackparrot_bd_1.$(BOARDNAME).tar.xz.b64

# Board IPs
IP_GROUP     = 192.168.3.
SERVER_IP    = $(IP_GROUP)100
FIRST        = 80
LAST         = 99
BOARDS       = $(addprefix $(IP_GROUP),$(shell seq -s " " $(FIRST) $(LAST)))
#BOARDS       = $(filter-out $(SERVER_IP),$(shell nmap -sn -oG - $(IP_GROUP)50-99 | awk '/Host:/ {print $$2}'))
#BOARDS       = 192.168.2.95 192.168.2.96 192.168.2.97 192.168.2.98
MY_IP        = $(shell ifconfig | awk '/$(IP_GROUP)/ {print $$2}' | head -1)

# Client credentials
CLIENT_UNAME = xilinx
CLIENT_PASS  = xilinx

empty :=
space := $(empty) $(empty)

define ssh_sessions
	ss | grep -i ':ssh' | awk '/:ssh/ {print $$6}' | grep -i '$(subst $(space),\|,$(BOARDS))'
endef

define ssh_wait
	@echo "Waiting for SSH jobs..."
        @until [ -z "$$($(call ssh_sessions))" ]; do \
		sleep 1; \
        done
	@echo "Done!"
endef

define ssh_barrier
	@if [ -n "$$($(call ssh_sessions))" ]; then \
		echo "SSH jobs running, please try again."; \
		exit 1; \
	fi
endef

define ssh2board
	sshpass -p "$(CLIENT_PASS)" ssh -o StrictHostKeychecking=no $(CLIENT_UNAME)@$1 $2 "echo $(CLIENT_PASS) | sudo -S $3"
endef

ifeq ($(SERVER_IP),$(MY_IP))

reboot_boards:
	@echo "The following boards will be rebooted: $(BOARDS)"
	@echo -n "Are you sure you want to reboot? All pending jobs will be terminated. [y/N] " && read ans && [ $${ans:-N} = y ]
	for ip in $(BOARDS); do \
                $(call ssh2board,$$ip,-f,reboot); \
        done

ping_boards:
	nmap -sn -oG - $(IP_GROUP)1-99

query_ssh:
	@echo $(shell $(call ssh_sessions))

#query_mem:
#	for ip in $(BOARDS); do \
#		$(call ssh2board,$$ip,,cat /proc/meminfo); \
#	done

$(SERVER_MNT)/%/zynq-parrot:
	git clone $(URL) $@ --branch $(BRANCH)

gen_dirs:
	git clone $(URL) $(SERVER_MNT)/zynq-parrot --branch $(BRANCH)
	mkdir -p $(SERVER_MNT)
	for ip in $(BOARDS); do \
		mkdir -p $(SERVER_MNT)/$$ip; \
		cp -r $(SERVER_MNT)/zynq-parrot $(SERVER_MNT)/$$ip/zynq-parrot; \
	done
	rm -rf $(SERVER_MNT)/zynq-parrot

clean_dirs:
	sudo rm -rf $(SERVER_MNT)/$(IP_GROUP)*

mount_boards:
	for ip in $(BOARDS); do \
		$(call ssh2board,$$ip,,mkdir -p $(BOARD_MNT)); \
		$(call ssh2board,$$ip,,mount $(SERVER_IP):$(SERVER_MNT) $(BOARD_MNT)); \
	done

unmount_boards:
	for ip in $(BOARDS); do \
		$(call ssh2board,$$ip,,umount $(BOARD_MNT)); \
	done

pre_run:
	$(call ssh_barrier)

load_bitstreams: pre_run
	for ip in $(BOARDS); do \
		$(call ssh2board,$$ip,-f,$(MAKE) -C $(BOARD_MNT) load_bitstream > /dev/null 2>&1); \
	done
	$(call ssh_wait)

%.run:
	@echo Running $($*_benchs) on $@
	$(call ssh2board,$*,-f,$(MAKE) -C $(BOARD_MNT) run_nbfs NBF_FILES=\"$(addsuffix .nbf,$(addprefix $(BOARD_MNT)/benchs/,$($*_benchs)))\" > /dev/null 2>&1)

run_benchs: pre_run $(foreach ip,$(BOARDS),$(ip).run)

else

ZPARROT_DIR = $(BOARD_MNT)/$(MY_IP)/zynq-parrot
EXAMPLE_DIR = $(ZPARROT_DIR)/cosim/$(EXAMPLE)
FPGA_DIR    = $(EXAMPLE_DIR)/fpga

$(EXAMPLE_DIR)/$(BITSTREAM): | $(ZPARROT_DIR)
	cp $(BOARD_MNT)/$(BITSTREAM) $@
	$(MAKE) -C $(FPGA_DIR) $(FPGA_ARGS) unpack_bitstream

load_bitstream: $(EXAMPLE_DIR)/$(BITSTREAM) | $(ZPARROT_DIR)
	cat /proc/meminfo > $(BOARD_MNT)/$(MY_IP)/load.log 2>&1
	$(MAKE) -C $(FPGA_DIR) $(FPGA_ARGS) unpack_bitstream >> $(BOARD_MNT)/$(MY_IP)/load.log 2>&1
	$(MAKE) -C $(FPGA_DIR) $(FPGA_ARGS) load_bitstream >> $(BOARD_MNT)/$(MY_IP)/load.log 2>&1

run: $(NBF_FILE) $(EXAMPLE_DIR)/$(BITSTREAM) | $(ZPARROT_DIR)
	$(MAKE) -C $(FPGA_DIR) $(FPGA_ARGS) load_bitstream > $(BOARD_MNT)/$(MY_IP)/$(notdir $<).load.log 2>&1
	$(MAKE) -C $(FPGA_DIR) $(FPGA_ARGS) run NBF_FILE=$< > $(BOARD_MNT)/$(MY_IP)/$(notdir $<).run.log 2>&1

run_nbfs: $(NBF_FILES)
	for nbf in $(NBF_FILES); do \
		$(MAKE) run NBF_FILE=$$nbf; \
	done

endif
