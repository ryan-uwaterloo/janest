`default_nettype none

module spi_top (

  input logic clk,
  input logic rst_n,

  // spi wires
  input  logic       sclk,
  input  logic       copi,
  input  logic       n_cs,
  output logic       cipo,

  // fifo to core connection
  input  logic [7:0]  core_req_addr,
  input  logic [15:0] core_req_data,
  input  logic        core_req_valid,
  output logic        core_req_ready,
  
  output logic [15:0] core_resp_data,
  output logic        core_resp_valid,
  input  logic        core_resp_ready,


  // fifo to memory connection
  output logic [15:0] mem_req_addr,
  output logic [15:0] mem_req_data,
  output logic        mem_req_valid,
  input  logic        mem_req_ready
);

  logic [7:0] in_pop_data;
  logic       in_pop_valid;
  logic       in_pop_ready;

  logic [7:0] out_pop_data;
  logic       out_pop_valid;
  logic       out_pop_ready;

  logic [7:0] in_push_data;
  logic       in_push_valid;
  logic       in_push_ready;

  logic [7:0] out_push_data;
  logic       out_push_valid;
  logic       out_push_ready;

  logic [params::FIFOS_W:0] in_free;
  logic [params::FIFOS_W:0] out_count;

  spi_fifos spi_fifos_inst (
    .clk(clk),
    .rst_n(rst_n),
    .in_pop_data(in_pop_data),
    .in_pop_valid(in_pop_valid),
    .in_pop_ready(in_pop_ready),
    .out_pop_data(out_pop_data),
    .out_pop_valid(out_pop_valid),
    .out_pop_ready(out_pop_ready),
    .in_push_data(in_push_data),
    .in_push_valid(in_push_valid),
    .in_push_ready(in_push_ready),
    .out_push_data(out_push_data),
    .out_push_valid(out_push_valid),
    .out_push_ready(out_push_ready),
    .in_free(in_free),
    .out_count(out_count)
  );

  logic [7:0] serdes_read_data;
  logic serdes_read_valid;
  logic serdes_tx_start;
  logic [7:0] serdes_write_data;
  logic serdes_write_ready;
  logic [3:0] serdes_max_writes, serdes_max_reads;

  spi_serdes spi_serdes_inst (
    .clk(clk),
    .rst_n(rst_n),
    .copi(copi),
    .n_cs(n_cs),
    .sclk(sclk),
    .cipo(cipo),
    .data(serdes_read_data),
    .valid(serdes_read_valid),
    .read_data(serdes_write_data),
    .read_next_byte(serdes_write_ready),
    .num_write_slots(serdes_max_writes),
    .num_read_slots(serdes_max_reads),
    .tx_start(serdes_tx_start)
  );

  logic pending_read;
  always_comb begin : host2fifo_ready
    if (core_req_valid) begin
      case (core_req_addr)
        extern_pkg::EXT_FIFO_FROM_HOST: core_req_ready = in_pop_valid & !pending_read;
        extern_pkg::EXT_FIFO_TO_HOST: core_req_ready = out_push_ready & !pending_read;
        default: core_req_ready = 1'b1;
      endcase
    end else core_req_ready = 1'b1;
  end

  logic fifo_read_valid, fifo_write_valid;
  assign fifo_read_valid = core_req_valid & core_req_ready & (core_req_addr == extern_pkg::EXT_FIFO_FROM_HOST);
  assign fifo_write_valid = core_req_valid & core_req_ready & (core_req_addr == extern_pkg::EXT_FIFO_TO_HOST);
  // assign core_resp_data = {{8{1'b0}}, in_pop_data};

  always_ff @(posedge clk ) begin : host2fifo_data
    if (!rst_n) begin
      pending_read <= '0;
      core_resp_valid <= '0;
    end else begin 
      core_resp_valid <= '0;
      if (fifo_read_valid | pending_read) begin
        core_resp_valid <= 1'b1;
        core_resp_data  <= {{8{1'b0}}, in_pop_data};
        if (core_resp_ready) begin
          pending_read <= 1'b0;
        end else begin
          pending_read <= 1'b1;
        end
      end
    end
  end

  assign in_pop_ready = (fifo_read_valid | pending_read) & core_resp_ready;
  assign out_push_valid = fifo_write_valid;
  assign out_push_data = core_req_data[7:0];

  typedef enum logic [1:0] { 
    IDLE = 2'h0,
    MEM  = 2'h1,
    FIFO = 2'h2
  } spi_state_t;

  spi_state_t spi_state;  
  spi_state_t next_spi_state;
  // logic [params::FIFOS_W-1:0] max_count;
  logic mem_bit;
  logic mem_addr_flag;
  logic [3:0] num_pending_writes, num_sent_reads;

  always_ff @(posedge clk ) begin : spi_state_handling_ff
    if (!rst_n) begin
      spi_state <= IDLE;

      mem_req_valid <= 1'b0;
      mem_req_addr <= '0;
      mem_req_data <= '0;

      mem_bit <= '0;
      mem_addr_flag <= '0;

      num_pending_writes <= '0;
      num_sent_reads <= '0;
    end else begin
      spi_state <= next_spi_state;

      mem_req_valid <= mem_req_valid & ~mem_req_ready; //hold valid until accepted
      if (spi_state == MEM & serdes_read_valid) begin
        mem_bit <= mem_bit + 1;
        if (~mem_addr_flag) begin
          if (mem_bit) begin 
            mem_req_addr[15:8] <= serdes_read_data;
            mem_addr_flag <= 1'b1;
          end else begin
            mem_req_addr[7:0] <= serdes_read_data;
          end
        end else begin
          if (mem_bit) begin
            mem_req_data[15:8] <= serdes_read_data;
            mem_req_valid <= 1'b1;
          end else begin
            mem_req_data[7:0] <= serdes_read_data;
          end
        end
      end
      if (mem_req_valid & mem_req_ready) begin
        mem_req_addr <= mem_req_addr + 2; // assumes byte addressable memory
      end

      if (spi_state == IDLE) begin
        mem_bit <= '0;
        mem_addr_flag <= '0;
        if (next_spi_state == FIFO) begin 
          num_pending_writes <= serdes_read_data[4:1] < serdes_max_writes ? serdes_read_data[4:1] : serdes_max_writes;
        end else begin 
          num_pending_writes <= '0;
          num_sent_reads <= '0;
        end
      end

      if (spi_state == FIFO) begin
        if (in_push_valid) num_pending_writes <= num_pending_writes - 1;
        if (out_pop_ready) num_sent_reads <= num_sent_reads + 1;
      end
    end
  end

  always_comb begin : spi_state_handling_comb
    out_pop_ready = 1'b0;
    in_push_valid = 1'b0;
    case (spi_state)
      IDLE: begin
        if (serdes_read_valid) begin
          next_spi_state = serdes_read_data[0] ? MEM : FIFO; // 8'01 = mem, 8'h00 = fifo
        end else next_spi_state = IDLE;
        serdes_write_data = {4'(in_free), 4'(out_count)};
      end
      MEM: begin
        serdes_write_data = 'x; // don't care
        next_spi_state = serdes_tx_start ? IDLE : MEM;
      end
      FIFO: begin
        serdes_write_data = out_pop_data;
        out_pop_ready = serdes_write_ready & (num_sent_reads != serdes_max_reads);
        in_push_valid = serdes_read_valid & (num_pending_writes != '0);
        next_spi_state = serdes_tx_start ? IDLE : FIFO;
      end
      default: next_spi_state = IDLE;
    endcase
  end

  assign in_push_data = serdes_read_data;

  // `ifndef SYNTHESIS
  //   assert (!(in_push_valid & !in_push_ready)) 
  //   else   $error("%m pushing to full in_fifo!!");
  // `endif SYNTHESIS
    
endmodule
