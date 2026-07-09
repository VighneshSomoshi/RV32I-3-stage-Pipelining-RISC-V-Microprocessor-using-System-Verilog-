// =============================================================
// wb_mux.sv
// Writeback Mux - Stage 3, final step before regfile write
//
// Selects the value to write into rd:
//   result_src = 1            -> memory load data
//   opcode = JAL/JALR (jump)  -> pc_next (return address)
//   opcode = LUI               -> imm_ext (immediate itself)
//   otherwise (result_src=0)  -> ALU result
// =============================================================

module wb_mux (
    input  logic [31:0] alu_result,
    input  logic [31:0] mem_read_data,
    input  logic [31:0] pc_next,
    input  logic [31:0] imm_ext,
    input  logic         result_src,
    input  logic         jump,
    input  logic [6:0]   opcode,

    output logic [31:0] write_data
);

    localparam logic [6:0] OPC_LUI = 7'b0110111;

    always_comb begin
        if (jump)
            write_data = pc_next;
        else if (opcode == OPC_LUI)
            write_data = imm_ext;
        else if (result_src)
            write_data = mem_read_data;
        else
            write_data = alu_result;
    end

endmodule