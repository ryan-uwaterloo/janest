# Verilator testbench runner.
#
#   make            build and run the testbench
#   make build      build only
#   make lint       lint the design (no testbench)
#   make clean
#
# Every directory is overridable, on the command line or in the environment:
#   make SRC_BUS=/src/BUS SRC_INC=/src/include TEST_DIR=/test/BUS
#
# Defaults are relative to wherever you run make from.

# Packages (isa_pkg, extern_pkg, BUS_flags_pkg, ...)
SRC_INC   ?= ../../src/include
# BUS RTL
SRC_BUS  ?= ../../src/bus
# FIFO RTL
SRC_MISC ?= ../../src/util
# Testbenches
TEST_DIR  ?= .
BUILD_DIR ?= build

# Top-level testbench module; its file is $(TEST_DIR)/$(TOP).sv unless TB_FILE is set
TOP       ?= tb_core_resp_arb
TB_FILE   ?= $(TEST_DIR)/$(TOP).sv

# Set to verilator-cli, a full path, etc. if yours differs
VERILATOR ?= verilator
VFLAGS    ?= -Wno-fatal -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-DECLFILENAME

# Packages first: SystemVerilog needs a package compiled before anything imports it.
# Add ordering here yourself if one package imports another
# (e.g. PKG_FILES = $(SRC_INC)/isa_pkg.sv $(SRC_INC)/BUS_flags_pkg.sv ...).
PKG_FILES  ?= $(sort $(wildcard $(SRC_INC)/*.sv))
BUS_FILES ?= $(sort $(wildcard $(SRC_BUS)/*.sv))
MISC_FILES ?= $(sort $(wildcard $(SRC_MISC)/*.sv))

ALL_FILES  := $(PKG_FILES) $(BUS_FILES) $(MISC_FILES) $(TB_FILE)
INCDIRS    := -I$(SRC_INC) -I$(SRC_BUS) -I$(SRC_MISC) -I$(TEST_DIR)
SIM        := $(BUILD_DIR)/V$(TOP)

.PHONY: all run build lint clean show
all: run

run: $(SIM)
	$(SIM) -WAVES=1

build: $(SIM)

$(SIM): $(ALL_FILES) | check
	$(VERILATOR) --binary --timing --trace $(VFLAGS) $(INCDIRS) \
	    --top-module $(TOP) -Mdir $(BUILD_DIR) $(ALL_FILES)

lint: | check
	$(VERILATOR) --lint-only -Wall $(VFLAGS) $(INCDIRS) $(PKG_FILES) $(BUS_FILES) $(MISC_FILES)

# Fail early with a readable message if a directory or file is wrong.
.PHONY: check
check:
	@test -n "$(PKG_FILES)"  || { echo "error: no .sv files in SRC_INC='$(SRC_INC)'";   exit 1; }
	@test -n "$(BUS_FILES)" || { echo "error: no .sv files in SRC_BUS='$(SRC_BUS)'"; exit 1; }
	@test -f "$(TB_FILE)"    || { echo "error: testbench '$(TB_FILE)' not found (TEST_DIR/TOP)"; exit 1; }

show:
	@echo "packages : $(PKG_FILES)"
	@echo "BUS     : $(BUS_FILES)"
	@echo "testbench: $(TB_FILE)  (top: $(TOP))"
	@echo "build dir: $(BUILD_DIR)"

clean:
	rm -rf $(BUILD_DIR)