// =============================================================
// id_stage.sv
// Instruction Decoder for 3-stage RISC-V (RV32I) pipeline
// Stage 2 input half: ID/EX combined stage
//
// Connects to if_stage as:
//   if_stage.instr_out -> id_stage.instr_in
//   if_stage.pc         -> id_stage.pc_in
//   if_stage.pc_next     -> id_stage.pc_next_in
//
// This module ONLY decodes + generates control signals + immediate.
// Register file read, ALU execute, and branch target add happen in
// separate modules (regfile.sv, alu.sv) driven by these outputs,
// all still conceptually inside the "ID/EX" pipeline stage.
// =============================================================

module id_stage (
    input  logic         clk,
    input  logic         reset,

    // from if_stage
    input  logic [31:0]  instr_in,
    input  logic [31:0]  pc_in,
    input  logic [31:0]  pc_next_in,

    // -------- decoded register addresses (to regfile) --------
    output logic [4:0]   rs1_addr,
    output logic [4:0]   rs2_addr,
    output logic [4:0]   rd_addr,

    // -------- raw instruction fields (to alu_control etc.) ----
    output logic [6:0]   opcode,
    output logic [2:0]   funct3,
    output logic [6:0]   funct7,

    // -------- immediate (to alu / branch target adder) --------
    output logic [31:0]  imm_ext,

    // -------- pass-through (to ID/EX -> MEM/WB pipeline reg) --
    output logic [31:0]  pc_out,
    output logic [31:0]  pc_next_out,

    // -------- control signals --------
    output logic         reg_write,    // write result to rd
    output logic         alu_src,      // 0 = rs2, 1 = imm
    output logic [3:0]   alu_op,       // operation select (to alu_control or alu directly)
    output logic         mem_read,     // load instruction
    output logic         mem_write,    // store instruction
    output logic         result_src,   // 0 = ALU result, 1 = memory data -> writeback mux
    output logic         branch,       // is a branch instruction (beq/bne/...)
    output logic         jump          // is a jump instruction (jal/jalr) -> later use with branch_target
);

    // =========================================================
    // RV32I opcode map (only the subset needed for base core)
    // =========================================================
    localparam logic [6:0] OPC_RTYPE  = 7'b0110011; // add, sub, and, or, xor, slt
    localparam logic [6:0] OPC_ITYPE  = 7'b0010011; // addi, andi, ori, slti
    localparam logic [6:0] OPC_LOAD   = 7'b0000011; // lw, lh, lb, lhu, lbu
    localparam logic [6:0] OPC_STORE  = 7'b0100011; // sw, sh, sb
    localparam logic [6:0] OPC_BRANCH = 7'b1100011; // beq, bne, blt, bge...
    localparam logic [6:0] OPC_JAL    = 7'b1101111;
    localparam logic [6:0] OPC_JALR   = 7'b1100111;
    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;

    // =========================================================
    // Field extraction (combinational, instruction is fixed layout)
    // =========================================================
    assign opcode   = instr_in[6:0];
    assign rd_addr  = instr_in[11:7];
    assign funct3   = instr_in[14:12];
    assign rs1_addr = instr_in[19:15];
    assign rs2_addr = instr_in[24:20];
    assign funct7   = instr_in[31:25];

    // pass PC values straight through to next pipeline register
    assign pc_out      = pc_in;
    assign pc_next_out = pc_next_in;

    // =========================================================
    // Immediate generator
    // Selects + sign-extends based on instruction format
    // =========================================================
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    assign imm_i = {{20{instr_in[31]}}, instr_in[31:20]};

    assign imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};

    assign imm_b = {{19{instr_in[31]}}, instr_in[31], instr_in[7],
                     instr_in[30:25], instr_in[11:8], 1'b0};

    assign imm_u = {instr_in[31:12], 12'b0};

    assign imm_j = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12],
                     instr_in[20], instr_in[30:21], 1'b0};

    always_comb begin
        unique case (opcode)
            OPC_ITYPE, OPC_LOAD, OPC_JALR : imm_ext = imm_i;
            OPC_STORE                     : imm_ext = imm_s;
            OPC_BRANCH                    : imm_ext = imm_b;
            OPC_LUI, OPC_AUIPC            : imm_ext = imm_u;
            OPC_JAL                       : imm_ext = imm_j;
            default                       : imm_ext = imm_i;
        endcase
    end

    // =========================================================
    // Control unit
    // Generates all control signals from opcode (+funct3 where
    // needed downstream by alu_control, which is a separate module)
    // =========================================================
    always_comb begin
        // safe defaults -> NOP-like behaviour for unknown opcodes
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        alu_op     = 4'b0000;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        result_src = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;

        unique case (opcode)
            OPC_RTYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;        // operand2 = rs2
                alu_op    = 4'b0010;     // generic "R-type" code, refine in alu_control using funct3/funct7
            end

            OPC_ITYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;        // operand2 = imm
                alu_op    = 4'b0010;
            end

            OPC_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;       // address = rs1 + imm
                alu_op     = 4'b0000;    // force add
                mem_read   = 1'b1;
                result_src = 1'b1;       // writeback comes from memory, not ALU
            end

            OPC_STORE: begin
                alu_src   = 1'b1;        // address = rs1 + imm
                alu_op    = 4'b0000;     // force add
                mem_write = 1'b1;
                // reg_write stays 0 - stores don't write a register
            end

            OPC_BRANCH: begin
                alu_src = 1'b0;          // compare rs1 vs rs2
                alu_op  = 4'b0001;       // force subtract/compare
                branch  = 1'b1;
                // reg_write stays 0
            end

            OPC_JAL, OPC_JALR: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                result_src = 1'b0;       // writeback = pc_next (handled by wb mux, not here)
                alu_src    = (opcode == OPC_JALR) ? 1'b1 : 1'b0;
            end

            OPC_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 4'b0011;     // pass imm through (lui = imm)
            end

            OPC_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 4'b0000;     // pc + imm, handled as add with pc as operand1 upstream
            end

            default: begin
                // unsupported / illegal instruction -> NOP behaviour
            end
        endcase
    end

endmodule