// =============================================================
// de_mem_reg.sv
// Pipeline register between Stage 2 (DE/EX) and Stage 3 (MEM/WB)
//
// Carries forward everything MEM/WB needs: ALU result (used as
// dmem address), rs2_data (used as dmem store data), destination
// register, and every control signal needed for memory access
// and writeback mux selection.
// =============================================================

module de_mem_reg (
    input  logic         clk,
    input  logic         reset,
    input  logic         flush,    // squash on mispredicted branch resolving late (not used in this 3-stage design but kept for safety)

    input  logic [31:0]  alu_result_in,
    input  logic [31:0]  rs2_data_in,
    input  logic [4:0]   rd_addr_in,
    input  logic [31:0]  pc_next_in,     // for jal/jalr writeback
    input  logic [31:0]  imm_ext_in,     // for lui writeback
    input  logic [2:0]   funct3_in,

    input  logic         reg_write_in,
    input  logic         mem_read_in,
    input  logic         mem_write_in,
    input  logic         result_src_in,  // 0 = ALU, 1 = mem data
    input  logic         jump_in,
    input  logic [6:0]   opcode_in,      // needed to tell LUI apart from jal/jalr for wb mux

    output logic [31:0]  alu_result_out,
    output logic [31:0]  rs2_data_out,
    output logic [4:0]   rd_addr_out,
    output logic [31:0]  pc_next_out,
    output logic [31:0]  imm_ext_out,
    output logic [2:0]   funct3_out,

    output logic         reg_write_out,
    output logic         mem_read_out,
    output logic         mem_write_out,
    output logic         result_src_out,
    output logic         jump_out,
    output logic [6:0]   opcode_out
);

    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            alu_result_out <= 32'h00000000;
            rs2_data_out   <= 32'h00000000;
            rd_addr_out    <= 5'd0;
            pc_next_out    <= 32'h00000000;
            imm_ext_out    <= 32'h00000000;
            funct3_out     <= 3'b000;
            reg_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            result_src_out <= 1'b0;
            jump_out       <= 1'b0;
            opcode_out     <= 7'b0000000;
        end
        else begin
            alu_result_out <= alu_result_in;
            rs2_data_out   <= rs2_data_in;
            rd_addr_out    <= rd_addr_in;
            pc_next_out    <= pc_next_in;
            imm_ext_out    <= imm_ext_in;
            funct3_out     <= funct3_in;
            reg_write_out  <= reg_write_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            result_src_out <= result_src_in;
            jump_out       <= jump_in;
            opcode_out     <= opcode_in;
        end
    end

endmodule