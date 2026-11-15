// Core -> extern request channel
interface core_req_if;
  logic [7:0]  addr;
  logic        core;
  logic [15:0] data;
  logic        valid;
  logic        ready;

  modport source (
    output addr, core, data, valid,
    input  ready
  );

  modport sink (
    input  addr, core, data, valid,
    output ready
  );

endinterface

// Extern -> Core response channel
interface core_resp_if;
  logic [15:0] data;
  logic        valid;
  logic        core;
  logic        ready;

  modport source (
    output data, valid, core,
    input  ready
  );

  modport sink (
    input  data, valid, core,
    output ready
  );

endinterface
