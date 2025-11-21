# Makefile to run TestSMT_RoundRobinPrefetch using Verilator
#
# Usage:
#   make -f Makefile.TestSMT_RoundRobinPrefetch.mk          # Build and run with defaults
#   make -f Makefile.TestSMT_RoundRobinPrefetch.mk build    # Build only
#   make -f Makefile.TestSMT_RoundRobinPrefetch.mk run      # Run existing build
#   make -f Makefile.TestSMT_RoundRobinPrefetch.mk clean    # Clean build artifacts
#   make -f Makefile.TestSMT_RoundRobinPrefetch.mk help     # Show options
#
# Parameters (override on command line):
#   MAX_TEST_CYCLES=<num>         Max simulation cycles (default: 2000)
#   TEST_CODE=<path>              Test code directory (default: Verification/TestCode/SMT_DualThread)
#   DUMMY_DATA_FILE=<path>        Dummy data file (default: Verification/DummyData.hex)
#   SHOW_PREFETCH_DEBUG=<0|1>     Show prefetch debug output (default: 0)

# Simulation parameters
MAX_TEST_CYCLES ?= 2000
TEST_CODE ?= Verification/TestCode/SMT_DualThread
DUMMY_DATA_FILE ?= Verification/DummyData.hex
SHOW_PREFETCH_DEBUG ?= 0

# Verilator configuration
ifndef RSD_VERILATOR_BIN
VERILATOR_BIN = verilator
else
VERILATOR_BIN = $(RSD_VERILATOR_BIN)
endif

# Paths
SOURCE_ROOT  = ./
TOOLS_ROOT   = ../Tools/
PROJECT_WORK = ../Project/Verilator
LIBRARY_WORK_RTL = $(PROJECT_WORK)/obj_dir_smt_rrprefetch
VERILATED_TOP_MODULE_NAME = VTestSMT_RoundRobinPrefetch

# Include core source code definition
include Makefiles/CoreSources.inc.mk

DEPS_RTL = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(MODULES:%=$(SOURCE_ROOT)%) \
	Verification/TestSMT_DualThreadRoundRobin.sv

# Disabled warnings
VERILATOR_DISABLED_WARNING = \
	-Wno-WIDTH \
	-Wno-INITIALDLY \
	-Wno-UNOPTFLAT \
	-Wno-TIMESCALEMOD

# RSD specific constants
RSD_VERILATOR_DEFINITION = \
	+define+RSD_FUNCTIONAL_SIMULATION \
	+define+RSD_FUNCTIONAL_SIMULATION_VERILATOR \
	$(RSD_SRC_CFG)

# Verilator options
VERILATOR_OPTION = \
	--cc \
	--binary \
	--assert \
	-sv \
	--top-module TestSMT_RoundRobinPrefetch \
	$(VERILATOR_DISABLED_WARNING) \
	$(RSD_VERILATOR_DEFINITION) \
	--Mdir $(LIBRARY_WORK_RTL) \
	+incdir+. \
	--trace \
	--trace-structs \
	-output-split 15000 \
	-j 0

VERILATOR_TARGET_CXXFLAGS = \
	-D RSD_FUNCTIONAL_SIMULATION_VERILATOR \
	-D RSD_FUNCTIONAL_SIMULATION \
	-D RSD_VERILATOR_TRACE \
	-D RSD_MARCH_FP_PIPE \
	-Wno-attributes

# Default target
.PHONY: all build run clean help

all: build run

build: $(LIBRARY_WORK_RTL) $(DEPS_RTL) Makefiles/CoreSources.inc.mk
	@echo "=== Building TestSMT_RoundRobinPrefetch ==="
	$(VERILATOR_BIN) $(VERILATOR_OPTION) $(DEPS_RTL)
	cd $(LIBRARY_WORK_RTL); \
		VPATH=../../../Src \
		CXXFLAGS="$(VERILATOR_TARGET_CXXFLAGS)" \
			$(MAKE) -f $(VERILATED_TOP_MODULE_NAME).mk
	@echo "=== Build Successful ==="

run:
	@echo "=== Running TestSMT_RoundRobinPrefetch ==="
	@echo "Parameters:"
	@echo "  MAX_TEST_CYCLES: $(MAX_TEST_CYCLES)"
	@echo "  TEST_CODE: $(TEST_CODE)"
	@echo "  DUMMY_DATA_FILE: $(DUMMY_DATA_FILE)"
	@echo "  SHOW_PREFETCH_DEBUG: $(SHOW_PREFETCH_DEBUG)"
	@echo ""
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		+MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
		+TEST_CODE=$(TEST_CODE) \
		+DUMMY_DATA_FILE=$(DUMMY_DATA_FILE) \
		+SHOW_PREFETCH_DEBUG=$(SHOW_PREFETCH_DEBUG)

$(LIBRARY_WORK_RTL):
	mkdir -p $(PROJECT_WORK)
	mkdir -p $(LIBRARY_WORK_RTL)

clean:
	rm -rf $(LIBRARY_WORK_RTL)
	@echo "=== Clean Complete ==="

help:
	@echo "TestSMT_RoundRobinPrefetch Makefile"
	@echo "===================================="
	@echo ""
	@echo "Round-Robin Prefetch Test for SMT Dual-Thread Architecture"
	@echo ""
	@echo "This testbench verifies:"
	@echo "  - Round-robin thread selection in fetch stage"
	@echo "  - Per-thread instruction prefetching"
	@echo "  - ROM/RAM initialization and access"
	@echo "  - PC progression for each thread"
	@echo ""
	@echo "Usage:"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk          Build and run"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk build    Build only"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk run      Run existing build"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk clean    Clean build artifacts"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk help     Show this help"
	@echo ""
	@echo "Parameters (override on command line):"
	@echo "  MAX_TEST_CYCLES=<num>         Max simulation cycles (default: 2000)"
	@echo "  TEST_CODE=<path>              Test code directory"
	@echo "                                (default: Verification/TestCode/SMT_DualThread)"
	@echo "  DUMMY_DATA_FILE=<path>        Dummy data file"
	@echo "                                (default: Verification/DummyData.hex)"
	@echo "  SHOW_PREFETCH_DEBUG=<0|1>     Show prefetch debug output (default: 0)"
	@echo ""
	@echo "Examples:"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=5000"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk build"
	@echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk SHOW_PREFETCH_DEBUG=1 run"
	@echo ""
	@echo "Output:"
	@echo "  Test report: $(TEST_CODE)/prefetch_roundrobin_report.txt"
	@echo "===================================="
