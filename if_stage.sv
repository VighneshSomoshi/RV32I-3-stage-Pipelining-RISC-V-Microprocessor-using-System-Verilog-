module if_stage (
    input  logic         clk,
    input  logic         reset,
  input  logic [31:0]  instr_in, // from instruction memory
    // optional control (later used for branch/jump)
    input  logic         pc_src,        // 0 = PC+4, 1 = branch target
    input  logic [31:0]  branch_target,
    output logic [31:0]  pc,
    output logic [31:0]  pc_next,
    output logic [31:0]  instr_out
);
    logic [31:0] pc_reg;

    // PC Register for sequential operations

    always_ff @(posedge clk or posedge reset) 
      begin
        if (reset)
            pc_reg <= 32'h00000000;
        else
            pc_reg <= pc_next;
    end

  // Next PC Logic (Combinational Operation)
    always_comb begin
      if (pc_src) //pc_src is a control signal

            pc_next = branch_target;   // for future branch/jump
        else
            pc_next = pc_reg + 32'd4;  // sequential execution
    end

    // Outputs

    assign pc        = pc_reg;
    assign instr_out = instr_in;
endmodule