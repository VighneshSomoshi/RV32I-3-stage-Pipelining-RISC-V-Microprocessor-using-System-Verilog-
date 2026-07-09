// =============================================================
// imem.sv
// Instruction Memory - simple synchronous-load, combinational-read
// ROM-style array. Drives if_stage.instr_in.
// =============================================================

module imem #(
    parameter int MEM_DEPTH_WORDS = 1024   // 1024 instructions
) (
    input  logic [31:0] addr,        // from if_stage.pc
    output logic [31:0] instr        // to if_stage.instr_in
);

    logic [31:0] mem [0:MEM_DEPTH_WORDS-1];

    // Load program at simulation start. Replace "program.hex" with
    // your actual test program file (one 32-bit hex word per line).
    initial begin
        $readmemh("program.hex", mem);
    end

    // word-aligned combinational read
    assign instr = mem[addr[31:2]];

endmodule