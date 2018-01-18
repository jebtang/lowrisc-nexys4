# See LICENSE for license details.

ifndef XILINX_VIVADO
$(error Please set environment variable XILINX_VIVADO for Xilinx tools)
endif

#--------------------------------------------------------------------
# global define
#--------------------------------------------------------------------

default: project

base_dir = $(abspath ../../..)
proj_dir = $(abspath .)
mem_gen = $(base_dir)/fpga/common/fpga_mem_gen
generated_dir = $(abspath ./generated-src)

glip_dir = $(base_dir)/opensocdebug/glip/src
osd_dir = $(base_dir)/opensocdebug/hardware
example_dir = $(base_dir)/fpga/bare_metal/examples

project_name = lowrisc-chip-imp
BACKEND ?= v
#CONFIG ?= Nexys4DebugConfig
CONFIG ?= LoRCNexys4Config

VIVADO = vivado

include $(base_dir)/Makefrag

.PHONY: default

#--------------------------------------------------------------------
# Sources
#--------------------------------------------------------------------

boot_mem = src/boot.mem
bootrom_img = $(base_dir)/bootrom/bootrom.img

lowrisc_srcs = \
	$(generated_dir)/$(MODEL).$(CONFIG).sv \
	$(generated_dir)/$(MODEL).$(CONFIG).behav_srams.sv \

lowrisc_headers = \
	$(generated_dir)/consts.vh \
	$(generated_dir)/consts.hpp \

verilog_srcs = \
	$(osd_dir)/interfaces/common/dii_channel.sv \
	$(base_dir)/src/main/verilog/chip_top.sv \
	$(base_dir)/src/main/verilog/spi_wrapper.sv \
	$(base_dir)/socip/nasti/channel.sv \
	$(base_dir)/socip/nasti/lite_nasti_reader.sv \
	$(base_dir)/socip/nasti/lite_nasti_writer.sv \
	$(base_dir)/socip/nasti/nasti_buf.sv \
	$(base_dir)/socip/nasti/nasti_combiner.sv \
	$(base_dir)/socip/nasti/nasti_crossbar.sv \
	$(base_dir)/socip/nasti/nasti_demux.sv \
	$(base_dir)/socip/nasti/nasti_lite_bridge.sv \
	$(base_dir)/socip/nasti/nasti_lite_reader.sv \
	$(base_dir)/socip/nasti/nasti_lite_writer.sv \
	$(base_dir)/socip/nasti/nasti_narrower.sv \
	$(base_dir)/socip/nasti/nasti_narrower_reader.sv \
	$(base_dir)/socip/nasti/nasti_narrower_writer.sv \
	$(base_dir)/socip/nasti/nasti_mux.sv \
	$(base_dir)/socip/nasti/nasti_slicer.sv \
	$(base_dir)/socip/util/arbiter.sv \
	$(base_dir)/vsrc/AsyncResetReg.v \
	$(base_dir)/vsrc/plusarg_reader.v \

#	$(base_dir)/vsrc/SimDTM_dummy.sv \

verilog_headers = \
	$(base_dir)/src/main/verilog/config.vh \
	$(base_dir)/socip/nasti/nasti_request.vh \

test_verilog_srcs = \
	$(base_dir)/src/test/verilog/host_behav.sv \
	$(base_dir)/src/test/verilog/nasti_ram_behav.sv \
	$(base_dir)/src/test/verilog/chip_top_tb.sv \

test_cxx_srcs = \
	$(base_dir)/src/test/cxx/common/globals.cpp \
	$(base_dir)/src/test/cxx/common/loadelf.cpp \
	$(base_dir)/src/test/cxx/common/dpi_ram_behav.cpp \
	$(base_dir)/src/test/cxx/common/dpi_host_behav.cpp \

test_cxx_headers = \
	$(base_dir)/src/test/cxx/common/globals.h \
	$(base_dir)/src/test/cxx/common/loadelf.hpp \
	$(base_dir)/src/test/cxx/common/dpi_ram_behav.h \
	$(base_dir)/src/test/cxx/common/dpi_host_behav.h \

#--------------------------------------------------------------------
# Build Verilog
#--------------------------------------------------------------------

verilog: $(lowrisc_srcs) $(lowrisc_headers)

include $(base_dir)/Makefrag-build

.PHONY: verilog
junk += $(generated_dir)

#--------------------------------------------------------------------
# Project generation
#--------------------------------------------------------------------

project = $(project_name)/$(project_name).xpr
project: $(project)
$(project): | $(lowrisc_srcs) $(lowrisc_headers)
	$(VIVADO) -mode batch -source script/make_project.tcl -tclargs $(project_name) $(CONFIG)
	ln -s $(proj_dir)/$(boot_mem) $(project_name)/$(project_name).runs/synth_1/boot.mem
	ln -s $(proj_dir)/$(boot_mem) $(project_name)/$(project_name).sim/sim_1/behav/boot.mem

vivado: $(project)
	$(VIVADO) $(project) &

bitstream = $(project_name)/$(project_name).runs/impl_1/chip_top.bit
bitstream: $(bitstream)
$(bitstream): $(lowrisc_srcs)  $(lowrisc_headers) $(verilog_srcs) $(verilog_headers) | $(project)
	$(VIVADO) -mode batch -source ../../common/script/make_bitstream.tcl -tclargs $(project_name)

program: $(bitstream)
	$(VIVADO) -mode batch -source ../../common/script/program.tcl -tclargs "xc7a100t_0" $(bitstream)

.PHONY: project vivado bitstream program

#--------------------------------------------------------------------
# DPI compilation
#--------------------------------------------------------------------
dpi_lib = $(project_name)/$(project_name).sim/sim_1/behav/xsim.dir/xsc/dpi.so
dpi: $(dpi_lib)
$(dpi_lib): $(test_verilog_srcs) $(test_cxx_srcs) $(test_cxx_headers)
	-mkdir -p $(project_name)/$(project_name).sim/sim_1/behav/xsim.dir/xsc
	cd $(project_name)/$(project_name).sim/sim_1/behav; \
	g++ -Wa,-W -fPIC -m64 -O1 -std=c++11 -shared -I$(XILINX_VIVADO)/data/xsim/include -I$(base_dir)/csrc/common \
	-DVERBOSE_MEMORY \
	$(test_cxx_srcs) $(XILINX_VIVADO)/lib/lnx64.o/librdi_simulator_kernel.so -o $(proj_dir)/$@

.PHONY: dpi

#--------------------------------------------------------------------
# FPGA simulation
#--------------------------------------------------------------------

sim-comp = $(project_name)/$(project_name).sim/sim_1/behav/compile.log
sim-comp: $(sim-comp)
$(sim-comp): $(lowrisc_srcs) $(lowrisc_headers) $(verilog_srcs) $(verilog_headers) $(test_verilog_srcs) $(test_cxx_srcs) $(test_cxx_headers) | $(project)
	cd $(project_name)/$(project_name).sim/sim_1/behav; source compile.sh > /dev/null
	@echo "If error, see $(project_name)/$(project_name).sim/sim_1/behav/compile.log for more details."

sim-elab = $(project_name)/$(project_name).sim/sim_1/behav/elaborate.log
sim-elab: $(sim-elab)
$(sim-elab): $(sim-comp) $(dpi_lib)
	cd $(project_name)/$(project_name).sim/sim_1/behav; source elaborate.sh > /dev/null
	@echo "If error, see $(project_name)/$(project_name).sim/sim_1/behav/elaborate.log for more details."

simulation: $(sim-elab)
	cd $(project_name)/$(project_name).sim/sim_1/behav; xsim tb_behav -key {Behavioral:sim_1:Functional:tb} -tclbatch $(proj_dir)/script/simulate.tcl -log $(proj_dir)/simulate.log

.PHONY: sim-comp sim-elab simulation

#--------------------------------------------------------------------
# Debug helper
#--------------------------------------------------------------------

search-ramb: src/boot.bmm
src/boot.bmm: $(bitstream)
	$(VIVADO) -mode batch -source ../../common/script/search_ramb.tcl -tclargs $(project_name) > search-ramb.log
	python ../../common/script/bmm_gen.py search-ramb.log src/boot.bmm 128 65536

bit-update: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit
$(project_name)/$(project_name).runs/impl_1/chip_top.new.bit: $(boot_mem) src/boot.bmm
	data2mem -bm $(boot_mem) -bd $< -bt $(bitstream) -o b $@

program-updated: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit
	$(VIVADO) -mode batch -source ../../common/script/program.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit

cfgmem: $(project_name)/$(project_name).runs/impl_1/chip_top.bit
	$(VIVADO) -mode batch -source ../../common/script/cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.bit

cfgmem-updated: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit
	$(VIVADO) -mode batch -source ../../common/script/cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit

program-cfgmem: $(project_name)/$(project_name).runs/impl_1/chip_top.bit.mcs
	$(VIVADO) -mode batch -source ../../common/script/program_cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.bit.mcs

program-cfgmem-updated: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit.mcs
	$(VIVADO) -mode batch -source ../../common/script/program_cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit.mcs

etherboot: boot0001.bin ../../common/script/recvRawEth
	../../common/script/recvRawEth -r eth0 boot0001.bin

ethertest: test0001.bin ../../common/script/recvRawEth
	../../common/script/recvRawEth -r eth0 test0001.bin

ethersd: boot0000.bin ../../common/script/recvRawEth
	../../common/script/recvRawEth -r eth0 boot0000.bin

../../common/script/recvRawEth: ../../common/script/recvRawEth.c
	make -C ../../common/script

test0001.bin: $(TOP)/riscv-tools/make_test.sh
	$(TOP)/riscv-tools/make_test.sh 0001

boot0001.bin: $(TOP)/riscv-tools/make_root.sh $(TOP)/riscv-tools/initial_0001 $(TOP)/riscv-tools/linux-4.6.2/.config $(TOP)/riscv-tools/busybox-1.21.1/.config
	$(TOP)/riscv-tools/make_root.sh 0001

boot0000.bin: $(TOP)/riscv-tools/make_root.sh $(TOP)/riscv-tools/initial_0000 $(TOP)/riscv-tools/linux-4.6.2/.config $(TOP)/riscv-tools/busybox-1.21.1/.config
	$(TOP)/riscv-tools/make_root.sh 0000

$(TOP)/riscv-tools/linux-4.6.2:
	$(TOP)/riscv-tools/fetch_and_patch_linux.sh

$(TOP)/riscv-tools/busybox-1.21.1:
	$(TOP)/riscv-tools/fetch_and_patch_busybox.sh

$(TOP)/riscv-tools/linux-4.6.2/.config: $(TOP)/riscv-tools/linux-4.6.2/arch/riscv/configs/riscv64_lowrisc
	make -C $(TOP)/riscv-tools/linux-4.6.2 ARCH=riscv defconfig CONFIG_RV_LOWRISC=y

$(TOP)/riscv-tools/busybox-1.21.1/.config:
	$(TOP)/riscv-tools/fetch_and_patch_busybox.sh

.PHONY: search-ramb bit-update program-updated

#--------------------------------------------------------------------
# Load examples
#--------------------------------------------------------------------

EXAMPLES = hello trace boot dram sdcard jump flash selftest tag eth

examples/Makefile:
	-mkdir examples
	ln -s $(example_dir)/Makefile examples/Makefile

$(EXAMPLES):  $(lowrisc_headers) | examples/Makefile
	FPGA_DIR=$(proj_dir) BASE_DIR=$(example_dir) $(MAKE) -C examples $@.hex
	cp examples/$@.hex $(boot_mem) && $(MAKE) bit-update

.PHONY: $(EXAMPLES)

tests:  $(lowrisc_headers) | examples/Makefile
	FPGA_DIR=$(proj_dir) BASE_DIR=$(example_dir) $(MAKE) -C examples hello.hex selftest.hex
	riscv64-unknown-elf-size examples/hello.riscv
	riscv64-unknown-elf-size examples/selftest.riscv

#--------------------------------------------------------------------
# Clean up
#--------------------------------------------------------------------

clean:
	$(info To clean everything, including the Vivado project, use 'make cleanall')
	-rm -rf *.log *.jou $(junk)
	-$(MAKE) -C examples clean

cleanall: clean
	-rm -fr $(project)
	-rm -fr $(project_name)
	-rm -fr examples

.PHONY: clean cleanall
