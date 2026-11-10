// Per-core halt flags and shift-register control/status layouts.
// Generated from the "Flags", "ShiftRegCtrl" and "ShiftRegStatus" tables.
package core_flags_pkg;

  localparam int FLAGS_W = 16;
  typedef logic [FLAGS_W-1:0] flags_t;

  // Flag bit positions. Used by halt: res = ((flags ^ rs2) & rs1).
  // Masked flags are cleared when a halt completes; they can be immediately set again. Unique per core.
  typedef enum int unsigned {
    FLAG_READ_PINS0            = 0,
    FLAG_READ_PINS1            = 1,
    FLAG_READ_PINS2            = 2,
    FLAG_READ_PINS3            = 3,
    FLAG_OWN_CLKDIV_TOGGLE     = 4,
    FLAG_OTHER_CLKDIV_TOGGLE   = 5,
    FLAG_FIFO_TO_HOST_NOT_FULL = 6,
    FLAG_FIFO_FROM_HOST_NOT_EMPTY = 7,
    FLAG_MP0                   = 8,
    FLAG_MP1                   = 9,
    FLAG_MP2                   = 10,
    FLAG_MP3                   = 11,
    FLAG_OWN_WDT_EXPIRY        = 12,
    FLAG_SHIFT_OUT_READY       = 13,
    FLAG_SHIFT_IN_VALID        = 14,
    FLAG_HOST_CORE_START       = 15
  } flag_idx_e;

  // One-hot masks
  localparam flags_t FLAGM_READ_PINS0               = flags_t'(1) << FLAG_READ_PINS0;
  localparam flags_t FLAGM_READ_PINS1               = flags_t'(1) << FLAG_READ_PINS1;
  localparam flags_t FLAGM_READ_PINS2               = flags_t'(1) << FLAG_READ_PINS2;
  localparam flags_t FLAGM_READ_PINS3               = flags_t'(1) << FLAG_READ_PINS3;
  localparam flags_t FLAGM_OWN_CLKDIV_TOGGLE        = flags_t'(1) << FLAG_OWN_CLKDIV_TOGGLE;
  localparam flags_t FLAGM_OTHER_CLKDIV_TOGGLE      = flags_t'(1) << FLAG_OTHER_CLKDIV_TOGGLE;
  localparam flags_t FLAGM_FIFO_TO_HOST_NOT_FULL    = flags_t'(1) << FLAG_FIFO_TO_HOST_NOT_FULL;
  localparam flags_t FLAGM_FIFO_FROM_HOST_NOT_EMPTY = flags_t'(1) << FLAG_FIFO_FROM_HOST_NOT_EMPTY;
  localparam flags_t FLAGM_MP0                      = flags_t'(1) << FLAG_MP0;
  localparam flags_t FLAGM_MP1                      = flags_t'(1) << FLAG_MP1;
  localparam flags_t FLAGM_MP2                      = flags_t'(1) << FLAG_MP2;
  localparam flags_t FLAGM_MP3                      = flags_t'(1) << FLAG_MP3;
  localparam flags_t FLAGM_OWN_WDT_EXPIRY           = flags_t'(1) << FLAG_OWN_WDT_EXPIRY;
  localparam flags_t FLAGM_SHIFT_OUT_READY          = flags_t'(1) << FLAG_SHIFT_OUT_READY;
  localparam flags_t FLAGM_SHIFT_IN_VALID           = flags_t'(1) << FLAG_SHIFT_IN_VALID;
  localparam flags_t FLAGM_HOST_CORE_START          = flags_t'(1) << FLAG_HOST_CORE_START;

  // halt result
  function automatic flags_t halt_result(flags_t flags, logic [15:0] rs2, logic [15:0] rs1);
    return (flags ^ rs2) & rs1;
  endfunction

  // ---------------------------------------------------------------------------
  // ShiftRegCtrl (extern 0x12), struct is MSB first
  // ---------------------------------------------------------------------------
  typedef enum logic {
    BIT_ORDER_LSB_FIRST = 1'b0,
    BIT_ORDER_MSB_FIRST = 1'b1
  } bit_order_e;

  typedef struct packed {
    logic [3:0]  rx_buffer_size;  // [15:12]
    logic        gapless;         // [11]
    logic        tx_idle_level;   // [10]
    logic        clk_out_en;      // [9]
    logic        rx_clkdiv_sel;   // [8]
    logic        tx_clkdiv_sel;   // [7]
    logic        rx_en;           // [6]
    logic        tx_en;           // [5] play valid buffers, then set tx_idle_level
    bit_order_e  bit_order;       // [4] shared by read and write
    logic [3:0]  tx_buffer_size;  // [3:0]
  } shiftreg_ctrl_t;

  // ---------------------------------------------------------------------------
  // ShiftRegStatus (extern 0x13), struct is MSB first
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [10:0] reserved;   // [15:5]
    logic        overrun;    // [4] sticky; cleared on read
    logic        underrun;   // [3] sticky; cleared on read
    logic        rx_valid;   // [2]
    logic        tx_ready;   // [1]
    logic        tx_busy;    // [0]
  } shiftreg_status_t;

endpackage : core_flags_pkg
