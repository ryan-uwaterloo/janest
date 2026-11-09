// ISA definition: 16-bit instructions, 16 registers (4-bit specifiers).
// Generated from the ISA spreadsheet.
package isa_pkg;

  localparam int INSTR_W = 16;
  localparam int REG_W   = 4;
  localparam int DATA_W  = 16;
  localparam int PC_W    = 9;   // pc offsets are 9'{offset, 1'b0}; instructions are 2-byte aligned

  typedef logic [INSTR_W-1:0] instr_t;
  typedef logic [REG_W-1:0]   reg_t;
  typedef logic [DATA_W-1:0]  data_t;
  typedef logic [7:0]         extern_addr_t;

  // ---------------------------------------------------------------------------
  // Primary opcode, instr[15:12]
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_WRE  = 4'b0000,  // external data @ extern_addr = rs2
    OP_BR   = 4'b0001,  // cmp / branches / jr (sub-opcode in instr[11:8])
    OP_RDE  = 4'b0010,  // rd = external data @ extern_addr
    OP_LI   = 4'b0011,  // rd = imm (zero-extend)
    OP_LUI  = 4'b0100,  // rd[15:8] = imm
    OP_BNZ  = 4'b0101,  // pc += offset if rs1 != 0 (signed)
    OP_JAL  = 4'b0110,  // pc += offset, rd = pc + 2
    OP_HALT = 4'b0111,  // res = ((flags ^ rs2) & rs1); halt until res != 0; rd = res
    OP_ADD  = 4'b1000,  // rd = rs1 + rs2 (signed)
    OP_OR   = 4'b1001,  // rd = rs1 | rs2
    OP_XOR  = 4'b1010,  // rd = rs1 ^ rs2
    OP_AND  = 4'b1011,  // rd = rs1 & rs2
    OP_LSL  = 4'b1100,  // rd = rs1 << rs2 (unsigned)
    OP_ADDI = 4'b1101,  // rd = rs1 + sign_extend(imm4)
    OP_RSL  = 4'b1110,  // rd = rs1 >> rs2, 0-extend
    OP_RSA  = 4'b1111   // rd = rs1 >> rs2, msb-extend
  } opcode_e;

  // ---------------------------------------------------------------------------
  // Sub-opcode for OP_BR, instr[11:8]
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    BR_BEQ  = 4'b0000,  // pc += offset if equal flag set
    BR_BNE  = 4'b0001,  // pc += offset if equal flag not set
    BR_BLT  = 4'b0010,  // pc += offset if lessthan flag set (signed)
    BR_BGE  = 4'b0011,  // pc += offset if lessthan flag not set (signed)
    BR_BLTU = 4'b0100,  // pc += offset if lessthan flag set (unsigned)
    BR_BGEU = 4'b0101,  // pc += offset if lessthan flag not set (unsigned)
    BR_CMP  = 4'b1000,  // populate branch status from rs1, rs2; persists until next cmp
    BR_JR   = 4'b1001   // pc = {rs1[15:1], 1'b0}
  } br_op_e;

  // ---------------------------------------------------------------------------
  // Instruction formats (packed structs, MSB first)
  // ---------------------------------------------------------------------------

  // add, or, xor, and, lsl, rsl, rsa, halt
  typedef struct packed {
    opcode_e op;   // [15:12]
    reg_t    rd;   // [11:8]
    reg_t    rs1;  // [7:4]
    reg_t    rs2;  // [3:0]
  } r_type_t;

  // addi
  typedef struct packed {
    opcode_e   op;   // [15:12]
    reg_t      rd;   // [11:8]
    reg_t      rs1;  // [7:4]
    logic [3:0] imm; // [3:0] sign-extended
  } addi_type_t;

  // wre
  typedef struct packed {
    opcode_e      op;           // [15:12]
    extern_addr_t extern_addr;  // [11:4]
    reg_t         rs2;          // [3:0]
  } wre_type_t;

  // rde
  typedef struct packed {
    opcode_e      op;           // [15:12]
    reg_t         rd;           // [11:8]
    extern_addr_t extern_addr;  // [7:0]
  } rde_type_t;

  // li, lui
  typedef struct packed {
    opcode_e    op;   // [15:12]
    reg_t       rd;   // [11:8]
    logic [7:0] imm;  // [7:0]
  } imm8_type_t;

  // jal
  typedef struct packed {
    opcode_e    op;      // [15:12]
    reg_t       rd;      // [11:8]
    logic [7:0] offset;  // [7:0]
  } jal_type_t;

  // cmp
  typedef struct packed {
    opcode_e op;   // [15:12] = OP_BR
    br_op_e  br;   // [11:8]  = BR_CMP
    reg_t    rs1;  // [7:4]
    reg_t    rs2;  // [3:0]
  } cmp_type_t;

  // beq, bne, blt, bge, bltu, bgeu
  typedef struct packed {
    opcode_e    op;      // [15:12] = OP_BR
    br_op_e     br;      // [11:8]
    logic [7:0] offset;  // [7:0]
  } br_type_t;

  // jr
  typedef struct packed {
    opcode_e op;      // [15:12] = OP_BR
    br_op_e  br;      // [11:8]  = BR_JR
    reg_t    rs1;     // [7:4]
    logic [3:0] unused; // [3:0]
  } jr_type_t;

  // bnz: offset is split around rs1
  typedef struct packed {
    opcode_e    op;         // [15:12]
    logic [3:0] offset_hi;  // [11:8] offset[7:4]
    reg_t       rs1;        // [7:4]
    logic [3:0] offset_lo;  // [3:0]  offset[3:0]
  } bnz_type_t;

  // ---------------------------------------------------------------------------
  // Field extraction helpers
  // ---------------------------------------------------------------------------
  function automatic opcode_e get_op(instr_t i);       return opcode_e'(i[15:12]); endfunction
  function automatic br_op_e  get_br_op(instr_t i);    return br_op_e'(i[11:8]);   endfunction

  // Branch/bnz offset -> signed byte displacement: 9'{offset, 1'b0}
  function automatic logic [PC_W-1:0] br_displacement(logic [7:0] offset);
    return {offset, 1'b0};
  endfunction

  function automatic logic [7:0] bnz_offset(instr_t i);
    bnz_type_t b = bnz_type_t'(i);
    return {b.offset_hi, b.offset_lo};
  endfunction

  function automatic data_t sext_imm4(logic [3:0] imm);
    return {{(DATA_W-4){imm[3]}}, imm};
  endfunction

  // ---------------------------------------------------------------------------
  // Encoding helpers (handy for testbenches / assemblers)
  // ---------------------------------------------------------------------------
  function automatic instr_t enc_r(opcode_e op, reg_t rd, reg_t rs1, reg_t rs2);
    return {op, rd, rs1, rs2};
  endfunction

  function automatic instr_t enc_addi(reg_t rd, reg_t rs1, logic [3:0] imm);
    return {OP_ADDI, rd, rs1, imm};
  endfunction

  function automatic instr_t enc_wre(extern_addr_t addr, reg_t rs2);
    return {OP_WRE, addr, rs2};
  endfunction

  function automatic instr_t enc_rde(reg_t rd, extern_addr_t addr);
    return {OP_RDE, rd, addr};
  endfunction

  function automatic instr_t enc_li(reg_t rd, logic [7:0] imm);
    return {OP_LI, rd, imm};
  endfunction

  function automatic instr_t enc_lui(reg_t rd, logic [7:0] imm);
    return {OP_LUI, rd, imm};
  endfunction

  function automatic instr_t enc_jal(reg_t rd, logic [7:0] offset);
    return {OP_JAL, rd, offset};
  endfunction

  function automatic instr_t enc_cmp(reg_t rs1, reg_t rs2);
    return {OP_BR, BR_CMP, rs1, rs2};
  endfunction

  function automatic instr_t enc_br(br_op_e br, logic [7:0] offset);
    return {OP_BR, br, offset};
  endfunction

  function automatic instr_t enc_jr(reg_t rs1);
    return {OP_BR, BR_JR, rs1, 4'b0000};
  endfunction

  function automatic instr_t enc_bnz(reg_t rs1, logic [7:0] offset);
    return {OP_BNZ, offset[7:4], rs1, offset[3:0]};
  endfunction

endpackage : isa_pkg