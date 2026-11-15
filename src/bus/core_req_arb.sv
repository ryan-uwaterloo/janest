module core_req_arb (
  input logic clk,
  input logic rst_n,

  core_req_if.sink   in0,
  core_req_if.sink   in1,
  core_req_if.source out
);

  // last granted input: 0 = in0, 1 = in1
  logic last;
  logic grant1;

  always_comb begin
    grant1 = in1.valid & (~in0.valid | ~last);
  end

  always_comb begin
    out.valid = in0.valid | in1.valid;
    out.addr  = grant1 ? in1.addr : in0.addr;
    out.core  = grant1 ? in1.core : in0.core;
    out.data  = grant1 ? in1.data : in0.data;

    in0.ready = out.ready & ~grant1;
    in1.ready = out.ready &  grant1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) last <= 1'b1;   // in0 has priority after reset
    else if (out.valid & out.ready) last <= grant1;
  end

endmodule
