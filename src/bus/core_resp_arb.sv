module core_resp_arb #(
  parameter int N = params::NUM_EXTERN
) (
  core_resp_if.sink   in  [N],
  core_resp_if.source out [2]
);

  logic [15:0] in_data  [N];
  logic        in_valid [N];
  logic        in_core  [N];

  for (genvar i = 0; i < N; i++) begin : g_in
    assign in_data[i]  = in[i].data;
    assign in_valid[i] = in[i].valid;
    assign in_core[i]  = in[i].core;
  end

  logic [N-1:0] req   [2];
  logic [N-1:0] grant [2];

  for (genvar c = 0; c < 2; c++) begin : g_core
    for (genvar i = 0; i < N; i++) begin : g_req
      assign req[c][i] = in_valid[i] & (in_core[i] == 1'(c));
    end

    // lowest index wins
    assign grant[c] = req[c] & (~req[c] + 1'b1);

    logic [15:0] data_or;
    always_comb begin
      data_or = '0;
      for (int i = 0; i < N; i++) data_or |= {16{grant[c][i]}} & in_data[i];
    end

    assign out[c].valid = |req[c];
    assign out[c].data  = data_or;
    assign out[c].core  = 1'(c);
  end

  for (genvar i = 0; i < N; i++) begin : g_rdy
    assign in[i].ready = (grant[0][i] & out[0].ready)
                       | (grant[1][i] & out[1].ready);
  end

endmodule
