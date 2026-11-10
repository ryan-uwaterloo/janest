`default_nettype none

module spi_fifos (
    input  logic clk,
    input  logic rst_n,

    output logic [7:0] in_pop_data,
    output logic       in_pop_valid,
    input  logic       in_pop_ready,

    output logic [7:0] out_pop_data,
    output logic       out_pop_valid,
    input  logic       out_pop_ready,

    input  logic [7:0] in_push_data,
    input  logic       in_push_valid,
    output logic       in_push_ready,

    input  logic [7:0] out_push_data,
    input  logic       out_push_valid,
    output logic       out_push_ready,

    output logic [params::FIFOS_W-1:0] in_free,
    output logic [params::FIFOS_W-1:0] out_count
);

    logic in_empty;
    logic in_full;
    logic in_almost_empty;
    logic in_almost_full;
    logic in_push;
    logic in_pop;
    logic [params::FIFOS_W-1:0] in_count;
    logic in_underflow;
    logic in_overflow;

    sync_fifo #(
        .DEPTH(params::NUM_FIFOS), 
        .WIDTH(8)
    ) in_fifo (
        .clk(clk), 
        .rst_n(rst_n), 
        .push(in_push), 
        .wr_data(in_push_data),
        .full(in_full),
        .pop(in_pop),
        .rd_data(in_pop_data),
        .empty(in_empty),
        .almost_full(in_almost_full),
        .almost_empty(in_almost_empty),
        .count(in_count),
        .free(in_free),
        .underflow(in_underflow),
        .overflow(in_overflow)
    );

    logic out_empty;
    logic out_full;
    logic out_almost_empty;
    logic out_almost_full;
    logic out_push;
    logic out_pop;
    logic [params::FIFOS_W-1:0] out_free;
    logic out_underflow;
    logic out_overflow;

    sync_fifo #(
        .DEPTH(params::NUM_FIFOS), 
        .WIDTH(8)
    ) out_fifo (
        .clk(clk), 
        .rst_n(rst_n), 
        .push(out_push), 
        .wr_data(out_push_data),
        .full(out_full),
        .pop(out_pop),
        .rd_data(out_pop_data),
        .empty(out_empty),
        .almost_full(out_almost_full),
        .almost_empty(out_almost_empty),
        .count(out_count),
        .free(out_free),
        .underflow(out_underflow),
        .overflow(out_overflow)
    );

    assign in_pop_valid = ~in_empty;
    assign in_pop = in_pop_valid & in_pop_ready;

    assign in_push_ready = ~in_full;
    assign in_push = in_push_ready & in_push_valid;

    assign out_pop_valid = ~out_empty;
    assign out_pop = out_pop_valid & out_pop_ready;

    assign out_push_ready = ~out_full;
    assign out_push = out_push_ready & out_push_valid;

    logic _unused_in  = &{in_almost_empty, in_almost_full, in_count, in_underflow, in_overflow};
    logic _unused_out = &{out_almost_empty, out_almost_full, out_free, out_underflow, out_overflow};
    
endmodule
