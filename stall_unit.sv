// =============================================================
// stall_unit.sv
// Detects load-use hazard: instruction currently in IF/DE register
// (about to enter DE/EX, i.e. about to read regs) needs a register
// that the instruction currently in DE/EX (a load, about to enter
// MEM/WB) hasn't loaded from memory yet.
//
// On detection: freeze PC, freeze IF/DE register, and bubble the
// DE/EX outputs going into the DE/MEM pipeline register for one
// cycle (handled by gating reg_write/mem_read/mem_write to 0 in
// top module for that cycle, or simply via the flush input on
// de_mem_reg - top module wires this up).
// =============================================================

module stall_unit (
    input  logic         id_mem_read,   // mem_read for instruction currently in DE/EX (id_stage output)
    input  logic [4:0]   id_rd_addr,    // its destination register
    input  logic [4:0]   if_rs1_addr,   // rs1 of instruction about to be decoded (raw instr_in[19:15] in IF/DE reg)
    input  logic [4:0]   if_rs2_addr,   // rs2 of instruction about to be decoded

    output logic         stall          // 1 = freeze PC + IF/DE reg, bubble DE/MEM reg
);

    always_comb begin
        stall = id_mem_read &&
                (id_rd_addr != 5'd0) &&
                ((id_rd_addr == if_rs1_addr) || (id_rd_addr == if_rs2_addr));
    end

endmodule