// =============================================================
// dmem.sv
// Data Memory for the MEM/WB stage
//
// Used by load (lw, lh, lb, lhu, lbu) and store (sw, sh, sb)
// instructions. Address and store data come from the ALU result
// and rs2_data that were computed back in the ID/EX stage and
// carried forward through the ID/EX -> MEM/WB pipeline register.
//
// Connects as:
//   ide_mem_reg.alu_result_out -> dmem.addr
//   ide_mem_reg.rs2_data_out   -> dmem.write_data
//   ide_mem_reg.mem_read_out   -> dmem.mem_read
//   ide_mem_reg.mem_write_out  -> dmem.mem_write
//   ide_mem_reg.funct3_out     -> dmem.funct3
//
//   dmem.read_data -> wb_mux (one of its inputs, selected by result_src)
//
// funct3 encodes the access size + signedness for RV32I loads/stores:
//   000 = byte  (lb / sb)      - sign-extended on load
//   001 = half  (lh / sh)      - sign-extended on load
//   010 = word  (lw / sw)
//   100 = byte unsigned (lbu)  - zero-extended on load
//   101 = half unsigned (lhu)  - zero-extended on load
// =============================================================

module dmem #(
    parameter int MEM_DEPTH_BYTES = 4096   // 4KB default data memory
) (
    input  logic         clk,
    input  logic         reset,

    // address + control, from ID/EX -> MEM/WB pipeline register
    input  logic [31:0]  addr,
    input  logic [31:0]  write_data,
    input  logic         mem_read,
    input  logic         mem_write,
    input  logic [2:0]   funct3,

    // result, goes to writeback mux
    output logic [31:0]  read_data
);

    // byte-addressable memory array
    localparam int NUM_BYTES = MEM_DEPTH_BYTES;
    logic [7:0] mem [0:NUM_BYTES-1];

    // word-aligned index for convenience
    logic [31:0] word_addr;
    assign word_addr = {addr[31:2], 2'b00};  // align down to word boundary

    // =========================================================
    // Reset / init (simulation only - synthesis tools will
    // usually ignore this loop or require a separate init file)
    // =========================================================
    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < NUM_BYTES; i = i + 1)
                mem[i] <= 8'h00;
        end
        // -----------------------------------------------------
        // Store (write) - synchronous, on clock edge
        // -----------------------------------------------------
        else if (mem_write) begin
            unique case (funct3)
                3'b000: begin // sb - store byte
                    mem[addr] <= write_data[7:0];
                end
                3'b001: begin // sh - store halfword
                    mem[addr]     <= write_data[7:0];
                    mem[addr + 1] <= write_data[15:8];
                end
                3'b010: begin // sw - store word
                    mem[addr]     <= write_data[7:0];
                    mem[addr + 1] <= write_data[15:8];
                    mem[addr + 2] <= write_data[23:16];
                    mem[addr + 3] <= write_data[31:24];
                end
                default: begin
                    // unsupported store size - do nothing
                end
            endcase
        end
    end

    // =========================================================
    // Load (read) - combinational, with sign/zero extension
    // mem_read gates whether read_data is meaningful; when not
    // a load instruction, read_data is forced to 0 to avoid
    // accidentally feeding garbage into the writeback mux if
    // result_src is mis-set.
    // =========================================================
    logic [7:0]  byte_rd;
    logic [15:0] half_rd;
    logic [31:0] word_rd;

    assign byte_rd = mem[addr];
    assign half_rd = {mem[addr + 1], mem[addr]};
    assign word_rd = {mem[addr + 3], mem[addr + 2], mem[addr + 1], mem[addr]};

    always_comb begin
        if (!mem_read) begin
            read_data = 32'h00000000;
        end
        else begin
            unique case (funct3)
                3'b000:  read_data = {{24{byte_rd[7]}},  byte_rd};   // lb  - sign extend
                3'b001:  read_data = {{16{half_rd[15]}}, half_rd};   // lh  - sign extend
                3'b010:  read_data = word_rd;                         // lw
                3'b100:  read_data = {24'b0, byte_rd};                // lbu - zero extend
                3'b101:  read_data = {16'b0, half_rd};                // lhu - zero extend
                default: read_data = 32'h00000000;
            endcase
        end
    end

endmodule