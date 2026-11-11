`default_nettype none
// SPI peripheral: deserializer (COPI -> frame fields) + serializer (read data -> CIPO).
//
// Timing limits (inherent to a peripheral that samples sclk with clk, not
// clocked by sclk itself):
//   - CIPO changes about CDC_LEN+2 clk cycles after the pin's sclk falling
//     edge; that must fit inside half an sclk period with margin
//     (roughly sclk <= clk/10 for CDC_LEN = 2).
// Runs in SPI Mode 0
module spi_serdes #(
    parameter int   CDC_LEN   = 2      // synchronizer depth for sclk / copi / n_cs
) (
    input  logic       clk,
    input  logic       sclk,
    input  logic       copi,
    input  logic       n_cs,
    input  logic       rst_n,
    output logic       cipo,

    output logic [7:0] data,
    output logic       valid,           // high from the last bit until the next frame's first bit

    // read path
    output logic       tx_start,        // high when first byte (read fifo status), low otherwise
    input  logic [7:0] read_data,       // sampled once at the first data-phase falling edge
    output logic       read_next_byte,  // when issuing last bit of current byte, request next
    output logic [3:0] num_write_slots, // the number of write slots captured
    output logic [3:0] num_read_slots   // the number of reads scheduled to be sent
);

  // ---------------------------------------------------------------------------
  // Synchronizers. sclk has one extra stage, so an sclk edge is detected one
  // clk cycle after it reaches the last copi / n_cs stage. copi is therefore
  // sampled one clk cycle after the real sclk rising edge, which is safe in
  // mode 0 because the master only changes COPI on the falling edge (same
  // alignment as the original deserializer).
  // ---------------------------------------------------------------------------
  logic [CDC_LEN:0]   sclk_sync;
  logic [CDC_LEN-1:0] copi_sync;
  logic [CDC_LEN:0] n_cs_sync;

  always_ff @(posedge clk) begin
    sclk_sync[0] <= sclk;
    copi_sync[0] <= copi;
    n_cs_sync[0] <= n_cs;
    for (int i = 1; i < CDC_LEN; i++) begin
      sclk_sync[i] <= sclk_sync[i-1];
      copi_sync[i] <= copi_sync[i-1];
      n_cs_sync[i] <= n_cs_sync[i-1];
    end
    sclk_sync[CDC_LEN] <= sclk_sync[CDC_LEN-1];
    n_cs_sync[CDC_LEN] <= n_cs_sync[CDC_LEN-1];
  end

  logic cs_active, cs_start, sclk_rise, sclk_fall, copi_s;
  assign cs_active = ~n_cs_sync[CDC_LEN-1];
  assign cs_start  = n_cs_sync[CDC_LEN] & cs_active;
  assign sclk_rise =  ~sclk_sync[CDC_LEN] & sclk_sync[CDC_LEN-1] & cs_active;
  assign sclk_fall = sclk_sync[CDC_LEN] &  ~sclk_sync[CDC_LEN-1] & cs_active;
  assign copi_s    =  copi_sync[CDC_LEN-1];

  // ---------------------------------------------------------------------------
  // SPI SerDes
  // ---------------------------------------------------------------------------
  logic read_next_byte_int;
  logic [2:0] txn_count;
  logic [6:0] tx_shift;     // remaining read bits after bit 7

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      txn_count  <= 3'd7;
      valid      <= 1'b0;
      cipo       <= 1'b0;
      tx_shift   <= '0;
      tx_start   <= 1'b1;
      read_next_byte <= 1'b0;
      num_write_slots <= '0;
      num_read_slots <= '0;
      read_next_byte_int <= '0;
    end else begin
      read_next_byte <= 1'b0;
      valid <= 1'b0;

      if (cs_start) begin
        num_write_slots <= read_data[7:4];
        num_read_slots  <= read_data[3:0];
      end

      if (!cs_active) begin
        // CS released: drop any partial frame so the next one starts aligned.
        txn_count <= 3'd7;
        tx_start  <= 1'b1;
        cipo      <= 1'b0;

      end else if (cs_start | (read_next_byte_int & sclk_fall)) begin
        tx_start <= 1'b0; //clear start flag when we consume FIFO status
        cipo     <= read_data[7];
        tx_shift <= read_data[6:0];
        read_next_byte_int <= 0;
      end else if (sclk_rise) begin
        // ---- deserializer ----
        txn_count <= txn_count - 3'd1;
        valid     <= (txn_count == 3'd0);
        data      <= {data[6:0], copi_s};

      end else if (sclk_fall) begin
        // ---- serializer ----
          cipo     <= tx_shift[6];
          tx_shift <= {tx_shift[5:0], 1'b0};
        if (txn_count == '0) begin
          read_next_byte <= 1'b1;
          read_next_byte_int <= 1'b1;
        end
      end
    end
  end

endmodule : spi_serdes
