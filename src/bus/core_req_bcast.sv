module core_req_bcast #(
  parameter int N = params::NUM_EXTERN
) (
  core_req_if.sink   in,
  core_req_if.source out [N]
);

  logic [N-1:0] rdy;

  for (genvar i = 0; i < N; i++) begin : g_fan
    assign out[i].addr  = in.addr;
    assign out[i].core  = in.core;
    assign out[i].data  = in.data;
    assign out[i].valid = in.valid;
    assign rdy[i]       = out[i].ready;
  end

  assign in.ready = &rdy;

endmodule
