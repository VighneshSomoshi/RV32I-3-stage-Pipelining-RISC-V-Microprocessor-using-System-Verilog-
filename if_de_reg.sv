// =============================================================
// if_de_reg.sv
// Pipeline register between Stage 1 (IF) and Stage 2 (DE/EX)
//
// Adds two control inputs not present in the original if_stage:
//   stall - freeze (load-use hazard): hold current contents, do not
//           latch new instruction in (re-presents same instr next cycle)
//   flush - branch/jump misprediction: insert a bubble (NOP) instead
//           of the wrongly-fetched instruction
// =============================================================

module if_de_reg (
    input  logic         clk,
    input  logic         reset,
    input  logic         stall,
    input  logic         flush,

    input  logic [31:0]  instr_in,
    input  logic [31:0]  pc_in,
    input  logic [31:0]  pc_next_in,

    output logic [31:0]  instr_out,
    output logic [31:0]  pc_out,
    output logic [31:0]  pc_next_out
);

    localparam logic [31:0] NOP = 32'h00000013; // addi x0, x0, 0

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            instr_out   <= NOP;
            pc_out      <= 32'h00000000;
            pc_next_out <= 32'h00000004;
        end
        else if (flush) begin
            instr_out   <= NOP;
            pc_out      <= pc_in;
            pc_next_out <= pc_next_in;
        end
        else if (stall) begin
            // hold current values - do nothing
        end
        else begin
            instr_out   <= instr_in;
            pc_out      <= pc_in;
            pc_next_out <= pc_next_in;
        end
    end

endmodule