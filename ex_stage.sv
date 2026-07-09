module ex_stage (
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm_ext,

    input  logic [31:0] pc_in,

    input  logic        alu_src,
    input  logic [3:0]  alu_op,
    input  logic        branch,
    input  logic        jump,

    output logic [31:0] alu_result,
    output logic        zero,
    output logic [31:0] branch_target,
    output logic        pc_src
);

    logic [31:0] alu_b;
 
    // Operand selection
    assign alu_b = (alu_src) ? imm_ext : rs2_data;

    // ALU instantiation
   
    alu alu_inst (
        .a(rs1_data),
        .b(alu_b),
        .alu_op(alu_op),
        .result(alu_result),
        .zero(zero)
    );

    
    // Branch target calculation
   
    assign branch_target = pc_in + imm_ext;

  
    // PC source decision
    
    assign pc_src = (branch && zero) | jump;

endmodule