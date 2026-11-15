`default_nettype none

// =============================================================================
// tb_core_resp_arb.sv : self-checking testbench for core_resp_arb
//
//   1. stimulus / observation signals, bridged to the interface arrays
//   2. reference model, checked every cycle against the DUT (combinational DUT,
//      so stimulus applied 1 time unit after a clk edge is checked at the next edge)
//   3. directed tests
//   4. constrained-random cycles (no protocol rules, pure model comparison)
//   5. end-to-end test: protocol-compliant peripherals with packet queues,
//      checks routing, per-peripheral ordering, no loss / duplication
//
// Plusargs: +SEED=n
// Override N from the simulator command line (e.g. -GN=1, -GN=2, -GN=20)
// =============================================================================
module tb_core_resp_arb #(
  parameter int N           = params::NUM_EXTERN,
  parameter int RAND_CYCLES = 20000
);

  logic clk = 0;
  always #5 clk = ~clk;

  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // ---------------------------------------------------------------------------
  // 1. DUT + signal bridge
  // ---------------------------------------------------------------------------
  core_resp_if in_if  [N] ();
  core_resp_if out_if [2] ();

  core_resp_arb #(.N(N)) dut (.in(in_if), .out(out_if));

  logic        s_valid  [N];
  logic [15:0] s_data   [N];
  logic        s_core   [N];
  logic        s_oready [2];

  logic        i_ready  [N];
  logic        o_valid  [2];
  logic [15:0] o_data   [2];
  logic        o_core   [2];

  for (genvar i = 0; i < N; i++) begin : g_in
    assign in_if[i].valid = s_valid[i];
    assign in_if[i].data  = s_data[i];
    assign in_if[i].core  = s_core[i];
    assign i_ready[i]     = in_if[i].ready;
  end

  for (genvar c = 0; c < 2; c++) begin : g_out
    assign out_if[c].ready = s_oready[c];
    assign o_valid[c]      = out_if[c].valid;
    assign o_data[c]       = out_if[c].data;
    assign o_core[c]       = out_if[c].core;
  end

  // ---------------------------------------------------------------------------
  // error reporting
  // ---------------------------------------------------------------------------
  int    errors   = 0;
  string cur_test = "init";

  task automatic fail(input string msg);
    errors++;
    if (errors <= 50) $display("  ERROR @%0d [%s] %s", cyc, cur_test, msg);
  endtask

  // ---------------------------------------------------------------------------
  // 2. reference model
  //    per core c: winner = lowest-index peripheral with valid && core == c
  //    out[c].valid = a winner exists, out[c].data = winner's data
  //    in[i].ready  = i is the winner of core c && out[c].ready, for some c
  // ---------------------------------------------------------------------------
  task automatic check_cycle();
    int win [2];
    bit exp_rdy;

    for (int c = 0; c < 2; c++) begin
      win[c] = -1;
      for (int i = N - 1; i >= 0; i--)
        if (s_valid[i] && s_core[i] == 1'(c)) win[c] = i;

      if (o_valid[c] !== (win[c] >= 0))
        fail($sformatf("out[%0d].valid: got %b expected %b", c, o_valid[c], win[c] >= 0));
      if (o_core[c] !== 1'(c))
        fail($sformatf("out[%0d].core: got %b expected %0d", c, o_core[c], c));
      if (win[c] >= 0 && o_data[c] !== s_data[win[c]])
        fail($sformatf("out[%0d].data: got 0x%0h expected 0x%0h (winner %0d)",
                       c, o_data[c], s_data[win[c]], win[c]));
    end

    for (int i = 0; i < N; i++) begin
      exp_rdy = (win[0] == i && s_oready[0]) || (win[1] == i && s_oready[1]);
      if (i_ready[i] !== exp_rdy)
        fail($sformatf("in[%0d].ready: got %b expected %b", i, i_ready[i], exp_rdy));
    end
  endtask

  // ---------------------------------------------------------------------------
  // stimulus helpers
  // convention: every task starts and ends 1 time unit after a clk edge
  // ---------------------------------------------------------------------------
  task automatic step(input int n = 1);
    repeat (n) begin
      @(posedge clk);
      check_cycle();
      #1;
    end
  endtask

  // all peripherals idle; core/data get junk so a masked-by-valid bug shows up
  task automatic clear_stim();
    for (int i = 0; i < N; i++) begin
      s_valid[i] = 0;
      s_core[i]  = 1'($urandom);
      s_data[i]  = 16'($urandom);
    end
    s_oready[0] = 1;
    s_oready[1] = 1;
  endtask

  task automatic set_req(input int i, input bit c, input logic [15:0] d);
    s_valid[i] = 1;
    s_core[i]  = c;
    s_data[i]  = d;
  endtask

  // ---------------------------------------------------------------------------
  // 3. directed tests
  // ---------------------------------------------------------------------------
  task automatic t_idle();
    step(3);
  endtask

  // one peripheral at a time, to each core, with each output ready/stalled
  task automatic t_single();
    for (int c = 0; c < 2; c++) begin
      for (int i = 0; i < N; i++) begin
        clear_stim();
        set_req(i, 1'(c), 16'(16'hA000 + i));
        step();
        s_oready[c] = 0;
        step();
        s_oready[0] = 0; s_oready[1] = 0;
        step();
        s_oready[0] = 1; s_oready[1] = 1;
        step();
      end
    end
  endtask

  // everyone targets one core; lowest index wins as the lower ones drop out
  task automatic t_priority();
    for (int c = 0; c < 2; c++) begin
      for (int k = 0; k < N; k++) begin
        clear_stim();
        for (int i = k; i < N; i++) set_req(i, 1'(c), 16'(16'hB000 + i));
        step();
      end
    end
  endtask

  // peripherals alternate between cores: both outputs busy at once, every ready combination
  task automatic t_split_backpressure();
    for (int ph = 0; ph < 2; ph++) begin
      clear_stim();
      for (int i = 0; i < N; i++) set_req(i, 1'((i + ph) % 2), 16'(16'hC000 + i));
      for (int m = 0; m < 4; m++) begin
        s_oready[0] = m[0];
        s_oready[1] = m[1];
        step();
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // 4. constrained random against the model
  // ---------------------------------------------------------------------------
  task automatic t_rand(input int valid_pct, input int ready_pct, input int cycles);
    repeat (cycles) begin
      for (int i = 0; i < N; i++) begin
        s_valid[i] = (int'($urandom_range(99)) < valid_pct);
        s_core[i]  = 1'($urandom);
        s_data[i]  = 16'($urandom);
      end
      s_oready[0] = (int'($urandom_range(99)) < ready_pct);
      s_oready[1] = (int'($urandom_range(99)) < ready_pct);
      step();
    end
  endtask

  // ---------------------------------------------------------------------------
  // 5. end-to-end: protocol-compliant peripherals
  //    Each peripheral owns a queue of packets {id, seq} with a destination core.
  //    It presents the head, holds it until accepted, then moves on.
  //    Checked: right core, right data, per-peripheral order, nothing lost or
  //    duplicated, and input-side accepts match output-side fires every cycle.
  // ---------------------------------------------------------------------------
  // packet k of peripheral i is {i, k}; its destination core is drawn once, when
  // the peripheral starts presenting it, and then held until it is accepted
  int          sent       [N];   // packets accepted so far, i.e. the head's sequence number
  bit          head_core  [N];
  bit          presenting [N];
  int          fired_in   [N];
  int          fired_out  [N];

  task automatic e2e(input int pkts, input int ready_pct, input int gap_pct, input int core1_pct);
    int remaining, limit, t, id;

    for (int i = 0; i < N; i++) begin
      sent[i]       = 0;
      head_core[i]  = 0;
      presenting[i] = 0;
    end
    clear_stim();
    remaining = N * pkts;
    limit     = 100 * N * pkts + 1000;
    t         = 0;

    while (remaining > 0 && t < limit) begin
      // drive: a presented packet is held until it is accepted
      for (int i = 0; i < N; i++) begin
        if (!presenting[i] && sent[i] < pkts && int'($urandom_range(99)) >= gap_pct) begin
          presenting[i] = 1;
          head_core[i]  = 1'(int'($urandom_range(99)) < core1_pct);
        end
        if (presenting[i]) begin
          s_valid[i] = 1;
          s_data[i]  = {8'(i), 8'(sent[i])};
          s_core[i]  = head_core[i];
        end else begin
          s_valid[i] = 0;
          s_core[i]  = 1'($urandom);
          s_data[i]  = 16'($urandom);
        end
      end
      s_oready[0] = (int'($urandom_range(99)) < ready_pct);
      s_oready[1] = (int'($urandom_range(99)) < ready_pct);

      @(posedge clk);
      check_cycle();

      for (int i = 0; i < N; i++) begin
        fired_in[i]  = 0;
        fired_out[i] = 0;
      end

      // output side: what actually left the arbiter
      for (int c = 0; c < 2; c++) begin
        if (o_valid[c] === 1'b1 && s_oready[c]) begin
          id = int'(o_data[c][15:8]);
          if (id >= N) begin
            fail($sformatf("out[%0d] fired unknown id %0d (data 0x%0h)", c, id, o_data[c]));
          end else begin
            fired_out[id]++;
            if (!presenting[id]) begin
              fail($sformatf("out[%0d] fired packet from idle peripheral %0d", c, id));
            end else begin
              if (o_data[c] !== {8'(id), 8'(sent[id])})
                fail($sformatf("out[%0d] from %0d: got 0x%0h expected 0x%0h",
                               c, id, o_data[c], {8'(id), 8'(sent[id])}));
              if (head_core[id] != 1'(c))
                fail($sformatf("packet from %0d for core %0d appeared on out[%0d]",
                               id, head_core[id], c));
            end
          end
        end
      end

      // input side: what each peripheral saw accepted
      for (int i = 0; i < N; i++) begin
        if (s_valid[i] && i_ready[i]) begin
          fired_in[i]++;
          sent[i]++;
          presenting[i] = 0;
          remaining--;
        end
        if (fired_in[i] != fired_out[i])
          fail($sformatf("peripheral %0d: %0d accepts but %0d output fires",
                         i, fired_in[i], fired_out[i]));
      end

      #1;
      t++;
    end

    if (remaining > 0) fail($sformatf("timeout: %0d packets never delivered", remaining));
    clear_stim();
    step(3);   // must go quiet
  endtask

  // ---------------------------------------------------------------------------
  // runner
  // ---------------------------------------------------------------------------
  int n_run = 0, n_fail = 0, err0;

  task automatic run_start(input string name);
    cur_test = name;
    err0     = errors;
    n_run++;
    clear_stim();
  endtask

  task automatic run_end();
    if (errors != err0) begin
      n_fail++;
      $display("[FAIL] %s", cur_test);
    end else begin
      $display("[pass] %s", cur_test);
    end
  endtask

  initial begin
    int v;

    $dumpfile("core_resp_arb.vcd");
    $dumpvars();

    if ($value$plusargs("SEED=%d", v)) begin
      $display("seed = %0d", v);
      void'($urandom(v));
    end

    clear_stim();
    @(posedge clk); #1;

    run_start("idle");              t_idle();               run_end();
    run_start("single");            t_single();             run_end();
    run_start("priority");          t_priority();           run_end();
    run_start("split_backpressure"); t_split_backpressure(); run_end();

    run_start("rand_sparse");       t_rand(10, 50,  RAND_CYCLES);  run_end();
    run_start("rand_mid");          t_rand(50, 50,  RAND_CYCLES);  run_end();
    run_start("rand_dense");        t_rand(90, 90,  RAND_CYCLES);  run_end();
    run_start("rand_saturated");    t_rand(100, 100, RAND_CYCLES); run_end();
    run_start("rand_stalled");      t_rand(80, 10,  RAND_CYCLES);  run_end();

    run_start("e2e_streaming");     e2e(40, 100, 0,  50);   run_end();
    run_start("e2e_mixed");         e2e(40, 50,  30, 50);   run_end();
    run_start("e2e_slow_core");     e2e(30, 20,  0,  50);   run_end();
    run_start("e2e_all_core0");     e2e(30, 70,  10, 0);    run_end();
    run_start("e2e_all_core1");     e2e(30, 70,  10, 100);  run_end();

    $display("----------------------------------------------");
    $display("N=%0d: %0d tests, %0d failed, %0d errors", N, n_run, n_fail, errors);
    if (errors == 0) $display("PASS: all checks");
    else             $fatal(1, "FAILED");
    $finish;
  end

endmodule