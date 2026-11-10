`default_nettype none
// Generic synchronous FIFO, first-word-fall-through.
//
//  - count / free are registered and always describe the state at the start of
//    the current cycle (i.e. before any push/pop happening this cycle takes
//    effect). count + free == DEPTH at all times.
//
//  - rd_data always shows the oldest entry while !empty; pop consumes it
//    (matches a "read = pop" register-style interface).
//  - DEPTH may be any value >= 2 (not restricted to powers of two).
//  - push while full / pop while empty are ignored, and flagged by the
//    one-cycle overflow / underflow pulses.
//  - Push and pop in the same cycle is allowed when the FIFO is neither
//    full nor empty. A push while full is rejected even if a pop happens in
//    the same cycle (keeps full/empty purely registered).
//  - Synchronous active-low reset. Storage is not reset.
module sync_fifo #(
  parameter int WIDTH               = 8,
  parameter int DEPTH               = 16,
  // almost_full  asserts when count >= DEPTH - ALMOST_FULL_MARGIN
  parameter int ALMOST_FULL_MARGIN  = 1,
  // almost_empty asserts when count <= ALMOST_EMPTY_LEVEL
  parameter int ALMOST_EMPTY_LEVEL  = 1,
  localparam int PTR_W = $clog2(DEPTH),
  localparam int CNT_W = $clog2(DEPTH + 1)
) (
  input  logic               clk,
  input  logic               rst_n,

  // write side
  input  logic               push,
  input  logic [WIDTH-1:0]   wr_data,

  // read side
  input  logic               pop,
  output logic [WIDTH-1:0]   rd_data,   // valid while !empty

  // status
  output logic               full,
  output logic               empty,
  output logic               almost_full,
  output logic               almost_empty,
  output logic [CNT_W-1:0]   count,     // valid entries currently stored (0..DEPTH)
  output logic [CNT_W-1:0]   free,      // free slots (DEPTH - count), always count + free == DEPTH
  output logic               overflow,  // push attempted while full (1 cycle)
  output logic               underflow  // pop attempted while empty (1 cycle)
);

  if (DEPTH < 2) begin : g_chk_depth
    $fatal(1, "sync_fifo: DEPTH must be >= 2 (got %0d)", DEPTH);
  end
  if (ALMOST_FULL_MARGIN < 0 || ALMOST_FULL_MARGIN > DEPTH) begin : g_chk_af
    $fatal(1, "sync_fifo: ALMOST_FULL_MARGIN out of range");
  end
  if (ALMOST_EMPTY_LEVEL < 0 || ALMOST_EMPTY_LEVEL > DEPTH) begin : g_chk_ae
    $fatal(1, "sync_fifo: ALMOST_EMPTY_LEVEL out of range");
  end

  localparam logic [PTR_W-1:0] LAST_PTR  = PTR_W'(unsigned'(DEPTH - 1));
  localparam logic [CNT_W-1:0] CNT_FULL  = CNT_W'(unsigned'(DEPTH));

  logic [WIDTH-1:0] mem [DEPTH];
  logic [PTR_W-1:0] wr_ptr, rd_ptr;

  logic push_ok, pop_ok;
  assign push_ok = push && !full;
  assign pop_ok  = pop  && !empty;

  function automatic logic [PTR_W-1:0] next_ptr(logic [PTR_W-1:0] p);
    return (p == LAST_PTR) ? '0 : p + 1'b1;
  endfunction

  logic [CNT_W-1:0] count_next;
  always_comb begin
    count_next = count;
    case ({push_ok, pop_ok})
      2'b10:   count_next = count + 1'b1;
      2'b01:   count_next = count - 1'b1;
      default: count_next = count;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr       <= '0;
      rd_ptr       <= '0;
      count        <= '0;
      free         <= CNT_FULL;
      full         <= 1'b0;
      empty        <= 1'b1;
      almost_full  <= (DEPTH - ALMOST_FULL_MARGIN) <= 0;
      almost_empty <= 1'b1;   // count == 0 <= ALMOST_EMPTY_LEVEL (level >= 0)
      overflow     <= 1'b0;
      underflow    <= 1'b0;
    end else begin
      if (push_ok) begin
        mem[wr_ptr] <= wr_data;
        wr_ptr      <= next_ptr(wr_ptr);
      end
      if (pop_ok) rd_ptr <= next_ptr(rd_ptr);

      count        <= count_next;
      free         <= CNT_FULL - count_next;
      full       <= (count_next == CNT_FULL);
      empty        <= (count_next == '0);
      almost_full  <= (int'(count_next) >= DEPTH - ALMOST_FULL_MARGIN);
      almost_empty <= (int'(count_next) <= ALMOST_EMPTY_LEVEL);
      overflow     <= push && full;
      underflow    <= pop  && empty;
    end
  end

  assign rd_data = mem[rd_ptr];

endmodule : sync_fifo
