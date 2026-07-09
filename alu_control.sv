// =============================================================
// alu_control.sv
// Translates id_stage's coarse alu_op category + funct3/funct7
// into the specific 4-bit alu_op encoding that alu.sv expects.
//
// alu.sv encoding (target):
//   0000 ADD   0001 SUB   0010 AND   0011 OR
//   0100 XOR   0101 SLL   0110 SRL   0111 SRA   1000 SLT
//
// id_stage category encoding (source, alu_op_cat):
//   0000 = force ADD   (loads, stores, auipc, jal/jalr target calc)
//   0001 = force SUB   (branches - uses alu.zero flag for beq/bne)
//   0010 = R/I generic (decode further using funct3 + funct7)
//   0011 = pass-through (lui - top module forces operand a = 0)
// =============================================================

module alu_control (
    input  logic [3:0] alu_op_cat,  // from id_stage.alu_op
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic       is_rtype,    // 1 = R-type (funct7 valid for add/sub), 0 = I-type
    output logic [3:0] alu_op       // final code, to alu.sv
);

    always_comb begin
        unique case (alu_op_cat)
            4'b0000: alu_op = 4'b0000;  // force ADD
            4'b0001: alu_op = 4'b0001;  // force SUB (branch compare)
            4'b0011: alu_op = 4'b0000;  // LUI pass-through, done via ADD with a=0

            4'b0010: begin // R-type / I-type generic - use funct3
                unique case (funct3)
                    3'b000:  alu_op = (is_rtype && funct7[5]) ? 4'b0001 : 4'b0000; // SUB : ADD/ADDI
                    3'b001:  alu_op = 4'b0101; // SLL / SLLI
                    3'b010:  alu_op = 4'b1000; // SLT / SLTI
                    3'b011:  alu_op = 4'b1000; // SLTU/SLTIU - not separately modeled, treat as SLT
                    3'b100:  alu_op = 4'b0100; // XOR / XORI
                    3'b101:  alu_op = funct7[5] ? 4'b0111 : 4'b0110; // SRA : SRL
                    3'b110:  alu_op = 4'b0011; // OR / ORI
                    3'b111:  alu_op = 4'b0010; // AND / ANDI
                    default: alu_op = 4'b0000;
                endcase
            end

            default: alu_op = 4'b0000;
        endcase
    end

endmodule