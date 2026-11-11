// =============================================================================
// tb_spi_top.sv : first-pass testbench for spi_top (SPI <-> host peripheral)
//
// Structure
//   1. config / plusargs
//   2. signals + DUT
//   3. monitors      (always-on checks: resp hold, mem hold, resp/mem capture)
//   4. BFMs          (spi master, core req/resp driver, mem sink policy)
//   5. host model    (expected FIFO contents; computes expected status / N)
//   6. transactions  (host_txrx, host_imem, core_read_expect, core_push_checked)
//   7. tests         (t_*)  -- IDs match spi_top_test_plan.md
//   8. runner        (`RUN macro, +TEST=<task name> to run just one)
//
// Plusargs: +TEST=t_name  +SCLK_HALF=n  +IN_DEPTH=n  +SEED=n  +ITERS=n  +MAXCYC=n
//
// Protocol as modelled (see test plan for the open questions):
//   header[0]==1                -> WRITE_IMEM:  addr0, addr1, then {data0, data1}...
//   header == {3'b0,nw[3:0],0}  -> HOST_TX_RX:  CIPO returns {in_write_space, out_read_count}
//                                  N = max(out_read_count, min(in_write_space, nw)) data bytes
//   core FIFO addresses         -> EXT_FIFO_FROM_HOST (core pops) / EXT_FIFO_TO_HOST (core pushes)
// =============================================================================
module tb_spi_top;
  import extern_pkg::*;

  localparam logic [7:0] ADDR_FROM_HOST = EXT_FIFO_FROM_HOST;  // core reads  (host -> core)
  localparam logic [7:0] ADDR_TO_HOST   = EXT_FIFO_TO_HOST;    // core writes (core -> host)
  localparam logic [7:0] HDR_WRITE_IMEM = 8'b0000_0001;

  function automatic logic [7:0] hdr_txrx(input int nw);
    logic [3:0] n;
    n = nw[3:0];
    return {3'b000, n, 1'b0};
  endfunction
  function automatic int imin(input int a, input int b); return (a < b) ? a : b; endfunction
  function automatic int imax(input int a, input int b); return (a > b) ? a : b; endfunction

  // ---------------------------------------------------------------------------
  // 1. config
  // ---------------------------------------------------------------------------
  int sclk_half   = 8;     // clk cycles per sclk half period (sclk = clk / (2*sclk_half))
  int cs_setup    = 4;     // clk cycles between n_cs edge and first/last sclk activity
  int cs_gap      = 8;     // idle clk cycles with n_cs high between transactions
  int in_depth    = 4;     // host->core FIFO depth (discovered from the reset status byte)
  int out_depth   = 4;     // core->host FIFO depth (discovered by filling it)
  int rand_iters  = 200;
  int max_cycles  = 20_000_000;

  // ---------------------------------------------------------------------------
  // 2. signals + DUT
  // ---------------------------------------------------------------------------
  logic        clk = 0;
  logic        rst_n = 0;
  always #5 clk = ~clk;

  logic        sclk = 0, copi = 0, n_cs = 1;
  logic        cipo;

  logic [7:0]  core_req_addr  = '0;
  logic [15:0] core_req_data  = '0;
  logic        core_req_valid = 0;
  logic        core_req_ready;
  logic [15:0] core_resp_data;
  logic        core_resp_valid;
  logic        core_resp_ready = 1;

  logic [15:0] mem_req_addr, mem_req_data;
  logic        mem_req_valid;
  logic        mem_req_ready = 1;

  spi_top dut (.*);

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc > max_cycles) $fatal(1, "watchdog: exceeded %0d cycles", max_cycles);
  end

  // ---------------------------------------------------------------------------
  // error reporting
  // ---------------------------------------------------------------------------
  int    errors   = 0;
  string cur_test = "init";

  task automatic fail(input string msg);
    errors++;
    $display("  ERROR @%0d [%s] %s", cyc, cur_test, msg);
  endtask

  task automatic check_eq(input string what, input longint got, input longint exp);
    if (got !== exp) fail($sformatf("%s: got 0x%0h expected 0x%0h", what, got, exp));
  endtask

  // ---------------------------------------------------------------------------
  // 3. monitors
  // ---------------------------------------------------------------------------
  // core response channel: capture beats, check "held until accepted"
  logic [15:0] resp_data_q [$];
  int          resp_cyc_q  [$];
  logic        p_rv = 0, p_rr = 0;
  logic [15:0] p_rd = '0;
  always @(posedge clk) if (rst_n) begin
    if (core_resp_valid && core_resp_ready) begin
      resp_data_q.push_back(core_resp_data);
      resp_cyc_q.push_back(cyc);
    end
    if (p_rv && !p_rr) begin
      if (!core_resp_valid)               fail("core_resp_valid dropped before core_resp_ready");
      else if (core_resp_data !== p_rd)   fail("core_resp_data changed while held");
    end
    p_rv <= core_resp_valid; p_rr <= core_resp_ready; p_rd <= core_resp_data;
  end

  // memory request channel: capture fires, check "valid held until txn fires"
  logic [15:0] mem_addr_q [$];
  logic [15:0] mem_data_q [$];
  logic        p_mv = 0, p_mr = 0;
  logic [15:0] p_ma = '0, p_md = '0;
  always @(posedge clk) if (rst_n) begin
    if (mem_req_valid && mem_req_ready) begin
      mem_addr_q.push_back(mem_req_addr);
      mem_data_q.push_back(mem_req_data);
    end
    if (p_mv && !p_mr) begin
      if (!mem_req_valid)                                         fail("mem_req_valid dropped before mem_req_ready");
      else if (mem_req_addr !== p_ma || mem_req_data !== p_md)    fail("mem_req addr/data changed while held");
    end
    p_mv <= mem_req_valid; p_mr <= mem_req_ready; p_ma <= mem_req_addr; p_md <= mem_req_data;
  end

  // ---------------------------------------------------------------------------
  // 4. BFMs
  // ---------------------------------------------------------------------------
  // convention: every task starts and ends 1 time unit after a clk edge, so
  // stimulus never races the DUT's sampling edge.
  task automatic tick(input int n);
    repeat (n) @(posedge clk);
    #1;
  endtask

  // memory sink ready policy: stall_pct % chance per cycle of a stall of 1..stall_max cycles
  int mem_stall_pct = 0;
  int mem_stall_max = 40;
  int mem_stall_cnt = 0;
  always @(negedge clk) begin
    if (mem_stall_cnt > 0) begin
      mem_stall_cnt <= mem_stall_cnt - 1;
      mem_req_ready <= 1'b0;
    end else if (mem_stall_pct > 0 && int'($urandom_range(99)) < mem_stall_pct) begin
      mem_stall_cnt <= $urandom_range(mem_stall_max, 1);
      mem_req_ready <= 1'b0;
    end else begin
      mem_req_ready <= 1'b1;
    end
  end

  // ---- SPI master, mode 0 (CPOL=0, CPHA=0), MSB first ----
  task automatic spi_cs(input bit assert_cs);
    if (assert_cs) begin
      n_cs = 0;
      tick(cs_setup);
    end else begin
      tick(cs_setup);
      n_cs = 1;
      tick(cs_gap);
    end
  endtask

  task automatic spi_byte(input logic [7:0] tx, output logic [7:0] rx);
    for (int i = 7; i >= 0; i--) begin
      copi = tx[i];
      tick(sclk_half);
      rx[i] = cipo;          // sampled just before the rising edge
      sclk = 1;
      tick(sclk_half);
      sclk = 0;
    end
  endtask

  // ---- core request driver: hold valid until it fires or `timeout` cycles pass ----
  task automatic core_req(
        input logic [7:0] a,
        input logic [15:0] d,
        input int timeout,
        output bit fired,
        output int fire_cyc
    );
        fired = 0;
        fire_cyc = -1;

        // All callers should arrive 1 time unit after a posedge.
        core_req_addr  = a;
        core_req_data  = d;
        core_req_valid = 1;

        for (int t = 0; t < timeout && !fired; t++) begin
            @(posedge clk);

            if (core_req_valid && core_req_ready) begin
                fired = 1;
                fire_cyc = cyc;
            end
        end

        // Deassert away from the sampling edge.
        #1;
        core_req_valid = 0;

        // Guarantee a complete idle cycle before another request.
        tick(1);
    endtask

  // ---------------------------------------------------------------------------
  // 5. host model: what each FIFO should hold
  // ---------------------------------------------------------------------------
  logic [7:0] in_exp  [$];   // bytes written by the host, not yet read by the core
  logic [7:0] out_exp [$];   // bytes pushed by the core, not yet read by the host
  logic [7:0] tx_q    [$];   // scratch: payload for the next host_txrx
  logic [7:0] rx_q    [$];   // scratch: everything the host read in the last host_txrx
  logic [15:0] exp_mem_addr [$];
  logic [15:0] exp_mem_data [$];
  bit         imem_used = 0;
  int         n_write_resps = 0;   // resp beats seen for core writes (spec open: info only)

  // ---------------------------------------------------------------------------
  // 6. transactions
  // ---------------------------------------------------------------------------
  // HOST_TX_RX. num_writes comes from tx_q (padded with random bytes if short);
  // `extra` junk bytes are clocked beyond the expected length and must be ignored.
  task automatic host_txrx(input int num_writes, input int extra);
    logic [7:0] st, rx, txb;
    int space, cnt, w, n, nw;
    nw    = num_writes & 15;
    space = imin(in_depth - in_exp.size(), 15);
    cnt   = imin(out_exp.size(), 15);
    w     = imin(space, nw);
    n     = imax(cnt, w);
    while (tx_q.size() < w) tx_q.push_back(8'($urandom));
    rx_q.delete();

    spi_cs(1);
    spi_byte(hdr_txrx(nw), st);
    check_eq("status.in_write_space", st[7:4], space);
    check_eq("status.out_read_count", st[3:0], cnt);
    for (int i = 0; i < n + extra; i++) begin
      txb = (i < w) ? tx_q[i] : 8'($urandom);
      spi_byte(txb, rx);
      rx_q.push_back(rx);
    end
    spi_cs(0);

    for (int i = 0; i < w; i++) in_exp.push_back(tx_q[i]);
    for (int i = 0; i < cnt; i++) begin
      check_eq($sformatf("host read byte %0d", i), rx_q[i], out_exp[0]);
      void'(out_exp.pop_front());
    end
    tx_q.delete();
  endtask

  // WRITE_IMEM: `nwords` random words starting at `addr`; compares every mem fire so far.
  task automatic host_imem(input logic [15:0] addr, input int nwords);
    logic [7:0]  rx;
    logic [15:0] d;
    int          waited;
    imem_used = 1;
    spi_cs(1);
    spi_byte(HDR_WRITE_IMEM, rx);
    spi_byte(addr[7:0],  rx);
    spi_byte(addr[15:8], rx);
    for (int i = 0; i < nwords; i++) begin
      d = 16'($urandom);
      spi_byte(d[7:0],  rx);
      spi_byte(d[15:8], rx);
      exp_mem_addr.push_back(addr + 16'(2 * i));
      exp_mem_data.push_back(d);
    end
    spi_cs(0);
    waited = 0;
    while (mem_addr_q.size() < exp_mem_addr.size() && waited < 3000) begin tick(1); waited++; end
    check_eq("mem txn count", mem_addr_q.size(), exp_mem_addr.size());
    for (int i = 0; i < imin(mem_addr_q.size(), exp_mem_addr.size()); i++) begin
      check_eq($sformatf("mem[%0d].addr", i), mem_addr_q[i], exp_mem_addr[i]);
      check_eq($sformatf("mem[%0d].data", i), mem_data_q[i], exp_mem_data[i]);
    end
  endtask

  // core pops one byte. `ok`=0 when the request never became ready.
  task automatic core_read_byte(output logic [7:0] b, output bit ok);
    bit fired; int fc; int w;
    resp_data_q.delete(); resp_cyc_q.delete();
    core_req(ADDR_FROM_HOST, 16'h0000, 12, fired, fc);
    ok = fired; b = '0;
    if (fired) begin
      w = 0;
      while (resp_data_q.size() == 0 && w < 10) begin tick(1); w++; end
      if (resp_data_q.size() == 0) fail("read fired but no core_resp beat");
      else begin
        check_eq("resp[15:8] must be 0", resp_data_q[0][15:8], 0);
        check_eq("resp latency (cycles after req fire)", resp_cyc_q[0] - fc, 1);
        b = resp_data_q[0][7:0];
      end
    end
  endtask

  // core pops one byte and checks it against the model (also checks ready-ness)
  task automatic core_read_expect();
    logic [7:0] b; bit ok;
    core_read_byte(b, ok);
    if (in_exp.size() == 0) begin
      if (ok) fail("core read accepted while host->core FIFO empty");
    end else if (!ok) begin
      fail("core read not accepted although host->core FIFO has data");
    end else begin
      check_eq("core read data", b, in_exp[0]);
      void'(in_exp.pop_front());
    end
  endtask

  // core pushes one byte (random upper byte: only byte0 may be stored)
  task automatic core_push_checked(input logic [7:0] b);
    bit fired; int fc;
    resp_data_q.delete(); resp_cyc_q.delete();
    core_req(ADDR_TO_HOST, {8'($urandom), b}, 12, fired, fc);
    tick(3);                                   // let any write response land, then discard
    n_write_resps += resp_data_q.size();
    resp_data_q.delete(); resp_cyc_q.delete();
    if (out_exp.size() < out_depth) begin
      if (!fired) fail("core push not accepted although core->host FIFO has space");
      else        out_exp.push_back(b);
    end else if (fired) begin
      fail("core push accepted while core->host FIFO full");
    end
  endtask

  task automatic reset_dut();
    rst_n = 0; sclk = 0; copi = 0; n_cs = 1;
    core_req_valid = 0; core_resp_ready = 1; mem_stall_pct = 0; sclk_half = 8;
    tick(6);
    rst_n = 1;
    tick(6);
    in_exp.delete(); out_exp.delete(); tx_q.delete(); rx_q.delete();
    exp_mem_addr.delete(); exp_mem_data.delete();
    mem_addr_q.delete(); mem_data_q.delete();
    resp_data_q.delete(); resp_cyc_q.delete();
    imem_used = 0;
  endtask

  // learn FIFO depths from the DUT; everything else is checked against them
  task automatic discover_depths();
    logic [7:0] st; bit fired; int fc; int v;
    reset_dut();
    spi_cs(1); spi_byte(hdr_txrx(0), st); spi_cs(0);
    in_depth = st[7:4];
    if ($value$plusargs("IN_DEPTH=%d", v)) in_depth = v;
    out_depth = 0;
    for (int i = 0; i < 20; i++) begin
      core_req(ADDR_TO_HOST, 16'(i), 12, fired, fc);
      tick(3);
      if (!fired) break;
      out_depth++;
    end
    $display("discovered depths: host->core (in) = %0d, core->host (out) = %0d", in_depth, out_depth);
    if (in_depth  < 1 || in_depth  > 15) fail($sformatf("in_depth %0d not usable (need 1..15)", in_depth));
    if (out_depth < 1 || out_depth > 15) fail($sformatf("out_depth %0d not usable (need 1..15)", out_depth));
  endtask

  // ---------------------------------------------------------------------------
  // 7. tests
  // ---------------------------------------------------------------------------
  // ---- A: reset / status ----
  task automatic t_reset_status();                       // A1
    host_txrx(0, 0);
    host_txrx(0, 0);
    check_eq("no mem txns after reset", mem_addr_q.size(), 0);
    check_eq("no resp beats after reset", resp_data_q.size(), 0);
  endtask

  // ---- B: WRITE_IMEM ----
  task automatic t_imem_single();                        // B1
    host_imem(16'hA55A, 1);
  endtask

  task automatic t_imem_burst();                         // B2, B3
    host_imem(16'h0040, 8);
    host_imem(16'h1234, 5);     // second transaction restarts from its own address
  endtask

  task automatic t_imem_mem_stall();                     // B4
    mem_stall_pct = 4; mem_stall_max = 40;
    host_imem(16'h0200, 16);
    mem_stall_pct = 0;
  endtask

  // ---- C: host -> core ----
  task automatic t_host_write_basic();                   // C1
    tx_q = '{8'h11, 8'h22, 8'h33};
    host_txrx(3, 0);
    repeat (3) core_read_expect();
    core_read_expect();                                  // empty: must not be accepted
    host_txrx(0, 0);
  endtask

  task automatic t_host_write_full();                    // C2
    for (int i = 0; i < in_depth; i++) tx_q.push_back(8'(8'hA0 + i));
    host_txrx(in_depth, 0);
    tx_q = '{8'h55, 8'h66, 8'h77};
    host_txrx(3, 0);                                     // no space: N = 0, nothing written
    repeat (in_depth) core_read_expect();
    host_txrx(0, 0);
  endtask

  task automatic t_host_write_truncate();                // C3
    for (int i = 0; i < 15; i++) tx_q.push_back(8'(8'h40 + i));
    host_txrx(imin(15, in_depth + 3), 4);                // more than fits, plus junk past N
    repeat (in_depth + 1) core_read_expect();            // last one must be refused
    host_txrx(0, 0);
  endtask

  task automatic t_host_write_partial_space();           // C4
    tx_q = '{8'h01, 8'h02, 8'h03};
    host_txrx(imin(3, in_depth), 0);
    core_read_expect();                                  // frees one slot
    for (int i = 0; i < 15; i++) tx_q.push_back(8'(8'hC0 + i));
    host_txrx(in_depth, 0);                              // space = depth - leftover
    while (in_exp.size() > 0) core_read_expect();
    host_txrx(0, 0);
  endtask

  // ---- D: core -> host ----
  task automatic t_host_read_basic();                    // D1, D2 (random upper byte)
    core_push_checked(8'hDE); core_push_checked(8'hAD); core_push_checked(8'hBE);
    host_txrx(0, 0);
    host_txrx(0, 0);                                     // now empty
  endtask

  task automatic t_host_read_extra();                    // D3
    core_push_checked(8'h91); core_push_checked(8'h92);
    host_txrx(0, 3);                                     // reads past the available bytes
    host_txrx(0, 0);                                     // nothing left, nothing invented
  endtask

  task automatic t_core_write_full();                    // D4
    for (int i = 0; i < out_depth + 2; i++) core_push_checked(8'(8'h30 + i));
    host_txrx(0, 0);
    core_push_checked(8'hEE);                            // space again
    host_txrx(0, 0);
  endtask

  // ---- E: simultaneous read + write, N rule ----
  task automatic t_mixed_n_rule();                       // E1..E4
    // out_count (3) > writes (1): N = 3
    core_push_checked(8'hA1); core_push_checked(8'hA2); core_push_checked(8'hA3);
    tx_q = '{8'h5A};
    host_txrx(1, 0);
    // out_count (1) < min(space, 4): N follows the writes
    core_push_checked(8'hB1);
    for (int i = 0; i < 4; i++) tx_q.push_back(8'(8'h70 + i));
    host_txrx(4, 0);
    // nothing to do: N = 0
    while (in_exp.size() > 0) core_read_expect();
    host_txrx(0, 0);
    // writes with empty out FIFO, and no writes with data in out FIFO
    core_push_checked(8'hC1);
    host_txrx(0, 0);
    tx_q = '{8'h01, 8'h02};
    host_txrx(2, 0);
    while (in_exp.size() > 0) core_read_expect();
  endtask

  // ---- F: core interface ----
  task automatic t_core_ready_rules();                   // F1, F2
    core_read_expect();                                  // empty -> refused
    for (int i = 0; i < out_depth + 1; i++) core_push_checked(8'(i));
    host_txrx(0, 0);
    core_push_checked(8'h77);
  endtask

  task automatic t_core_nonmatching_addr();              // F3
    logic [7:0] bad [$];
    bit fired; int fc;
    bad = '{8'h00, 8'h01, 8'h04, 8'h05, 8'h0A, 8'h20, 8'hFF};
    tx_q = '{8'h3C};
    host_txrx(1, 0);
    core_push_checked(8'hC3);
    resp_data_q.delete(); resp_cyc_q.delete();
    foreach (bad[i]) begin
      core_req(bad[i], 16'hFFFF, 6, fired, fc);
      tick(4);
    end
    check_eq("resp beats for non-matching addresses", resp_data_q.size(), 0);
    host_txrx(0, 0);                                     // out FIFO unchanged (and read out)
    core_read_expect();                                  // in FIFO unchanged
  endtask

  task automatic t_resp_hold();                          // F4
    tx_q = '{8'h6B, 8'h6C};
    host_txrx(2, 0);
    core_resp_ready = 0;
    begin
      bit fired; int fc;
      resp_data_q.delete(); resp_cyc_q.delete();
      core_req(ADDR_FROM_HOST, 16'h0, 12, fired, fc);
      if (!fired) fail("read not accepted");
      check_eq("core_resp_valid next cycle", core_resp_valid, 1);
      check_eq("core_resp_data (held)", core_resp_data, 16'h006B);
      tick(10);
      check_eq("core_resp_valid still held", core_resp_valid, 1);
      check_eq("core_resp_data still held", core_resp_data, 16'h006B);
      check_eq("no beat while ready low", resp_data_q.size(), 0);
      core_resp_ready = 1;
      tick(1);
      check_eq("exactly one beat after release", resp_data_q.size(), 1);
      tick(2);
      check_eq("core_resp_valid cleared after accept", core_resp_valid, 0);
    end
    void'(in_exp.pop_front());
    core_read_expect();                                  // second byte still correct
  endtask

  // ---- R: constrained random against the model ----
  task automatic t_random();                             // R1
    int speeds [3];
    int k, nw, mw, ok_fifo;
    logic [15:0] a;
    speeds = '{8, 10, 16};
    for (int it = 0; it < rand_iters; it++) begin
      sclk_half = speeds[$urandom_range(2)];
      case ($urandom_range(3))
        0: begin k = $urandom_range(4); repeat (k) core_push_checked(8'($urandom)); end
        1: begin k = $urandom_range(4); repeat (k) core_read_expect(); end
        2: begin
             nw = $urandom_range(15);
             for (int i = 0; i < nw; i++) tx_q.push_back(8'($urandom));
             host_txrx(nw, $urandom_range(2));
           end
        3: begin
             a  = 16'($urandom) & 16'hFFFE;
             mw = $urandom_range(4, 1);
             host_imem(a, mw);
           end
      endcase
    end
    while (in_exp.size() > 0) core_read_expect();
    host_txrx(0, 0);
    host_txrx(0, 0);
  endtask

  // ---------------------------------------------------------------------------
  // 8. runner
  // ---------------------------------------------------------------------------
  `define RUN(name) \
    if (sel == "" || sel == `"name`") begin \
      cur_test = `"name`"; err0 = errors; reset_dut(); name(); \
      if (!imem_used && mem_addr_q.size() != 0) fail("unexpected mem_req activity"); \
      n_run++; \
      if (errors != err0) begin n_fail++; $display("[FAIL] %s", `"name`"); end \
      else $display("[pass] %s", `"name`"); \
    end

  string sel = "";
  int n_run = 0, n_fail = 0, err0;

  initial begin
    int v;

    $dumpfile("spi.vcd");
    $dumpvars();

    if ($value$plusargs("TEST=%s", sel)) ;
    if ($value$plusargs("SCLK_HALF=%d", v)) sclk_half = v;
    if ($value$plusargs("ITERS=%d", v))     rand_iters = v;
    if ($value$plusargs("MAXCYC=%d", v))    max_cycles = v;
    if ($value$plusargs("SEED=%d", v)) begin
      $display("seed = %0d", v);
      void'($urandom(v));
    end
    @(posedge clk); #1;

    discover_depths();

    `RUN(t_reset_status)
    `RUN(t_imem_single)
    `RUN(t_imem_burst)
    `RUN(t_imem_mem_stall)
    `RUN(t_host_write_basic)
    `RUN(t_host_write_full)
    `RUN(t_host_write_truncate)
    `RUN(t_host_write_partial_space)
    `RUN(t_host_read_basic)
    `RUN(t_host_read_extra)
    `RUN(t_core_write_full)
    `RUN(t_mixed_n_rule)
    `RUN(t_core_ready_rules)
    `RUN(t_core_nonmatching_addr)
    `RUN(t_resp_hold)
    `RUN(t_random)

    $display("----------------------------------------------");
    $display("%0d tests, %0d failed, %0d errors  (core writes produced %0d resp beats)",
             n_run, n_fail, errors, n_write_resps);
    if (errors == 0 && n_run > 0) $display("PASS: all checks");
    else                          $fatal(1, "FAILED");
    $finish;
  end
endmodule