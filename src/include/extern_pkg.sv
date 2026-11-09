// External address map accessed via rde / wre (8-bit address space).
// Generated from the "Extern Addrs" table.
package extern_pkg;

  typedef enum logic [7:0] {
    EXT_WRITE_PINS         = 8'h00,  // W: update all pins            | R: -
    EXT_READ_PINS          = 8'h01,  // W: ignored
    EXT_FIFO_FROM_HOST     = 8'h02,  // R: pop FIFO
    EXT_FIFO_TO_HOST       = 8'h03,  // W: push FIFO
    EXT_SHIFTREG_OUT       = 8'h04,  // W: push double buffer
    EXT_SHIFTREG_IN        = 8'h05,  // W: ignored
    EXT_MP_FLAGS           = 8'h06,  // message passing flags
    EXT_PARITY_ENGINE      = 8'h07,  // R: ready 1 cycle after write
    EXT_WDT0               = 8'h08,  // W: set timeout (cycles), start | R: expiry status
    EXT_WDT1               = 8'h09,  // W: set timeout (cycles), start | R: expiry status
    EXT_FIFO_STATUS        = 8'h0A,  // W: ignored
    EXT_CLKDIV0_EN         = 8'h0B,  // W: enabling resets counter to 0; toggling on next cycle
    EXT_CLKDIV1_EN         = 8'h0C,  // W: enabling resets counter to 0; toggling on next cycle
    EXT_PINS_OE            = 8'h0D,  // pins output enable
    EXT_CLKDIV0_B          = 8'h0E,
    EXT_CLKDIV0_C          = 8'h0F,
    EXT_CLKDIV1_B          = 8'h10,
    EXT_CLKDIV1_C          = 8'h11,
    EXT_SHIFTREG_CTRL      = 8'h12,  // see core_flags_pkg::shiftreg_ctrl_t
    EXT_SHIFTREG_STATUS    = 8'h13   // see core_flags_pkg::shiftreg_status_t
    // 0x14 - 0x1F: reserved
  } extern_addr_e;

  // Scratchpad region
  localparam logic [7:0] EXT_SCRATCH_BASE = 8'h20;
  localparam logic [7:0] EXT_SCRATCH_LAST = 8'hFF;

  function automatic logic is_scratchpad(logic [7:0] addr);
    return addr >= EXT_SCRATCH_BASE;  // upper bound is the top of the 8-bit space
  endfunction

endpackage : extern_pkg