// =============================================================
// branch_unit.sv
// Resolves branch/jump outcome and target address in Stage 2 (DE/EX)
//
// beq/bne use alu.zero (alu_control forces SUB for branches, so
// zero=1 means rs1==rs2). blt/bge etc. are not in the base subset
// per the theory doc, so only beq/bne are handled here; extend
// funct3 decoding later if you add blt/bge/bltu/bgeu.
// =============================================================

module branch_unit (
    input  logic [31:0] pc,          // current instruction's PC (from id_stage.pc_out)
    input  logic [31:0] imm_ext,     // branch/jump immediate (already correct format from id_stage)
    input  logic [31:0] alu_result,  // for jalr target (rs1 + imm)
    input  logic         alu_zero,
    input  logic [2:0]   funct3,
    input  logic         branch,     // instruction is beq/bne/...
    input  logic         jump,       // instruction is jal/jalr
    input  logic [6:0]   opcode,

    output logic [31:0] branch_target,
    output logic         pc_src       // 1 = take branch_target, 0 = PC+4
);

    localparam logic [6:0] OPC_JALR = 7'b1100111;

    logic branch_taken;

    always_comb begin
        unique case (funct3)
            3'b000:  branch_taken = alu_zero;       // beq
            3'b001:  branch_taken = !alu_zero;      // bne
            default: branch_taken = 1'b0;           // blt/bge/etc. not implemented yet
        endcase
    end

    always_comb begin
        if (opcode == OPC_JALR)
            branch_target = {alu_result[31:1], 1'b0};  // jalr target = (rs1+imm) with LSB cleared
        else
            branch_target = pc + imm_ext;               // jal / branch target = pc + imm
    end

    assign pc_src = jump || (branch && branch_taken);

endmodule