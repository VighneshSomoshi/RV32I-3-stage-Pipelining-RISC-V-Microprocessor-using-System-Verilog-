// =============================================================
// regfile.sv
// RV32I Register File: 32 x 32-bit registers, x0 hardwired to 0
//
// 2 read ports (combinational, asynchronous read)
// 1 write port (synchronous, on posedge clk)
//
// Connects to id_stage as:
//   id_stage.rs1_addr -> regfile.rs1_addr
//   id_stage.rs2_addr -> regfile.rs2_addr
//
// Write port is driven from the MEM/WB stage (NOT directly from
// id_stage.rd_addr, since the write happens 1 cycle later, after
// the destination register travels through the ID/EX -> MEM/WB
// pipeline register). Hence separate rd_addr_w / reg_write_w /
// write_data ports here.
//
// IMPORTANT - write-first behaviour:
// This module reads and writes in the SAME always_ff process using
// blocking-vs-nonblocking trickery is avoided; instead we use a
// simple "write-first" bypass on the read MUX so that if the
// instruction currently reading rs1/rs2 has the same address as
// the register being written THIS cycle, it sees the NEW value,
// not the stale one. This is the trick discussed earlier that
// removes most RAW stalls in a 3-stage pipeline without needing
// a separate forwarding unit.
// =============================================================

module regfile (
    input  logic         clk,
    input  logic         reset,

    // -------- read port 1 --------
    input  logic [4:0]   rs1_addr,
    output logic [31:0]  rs1_data,

    // -------- read port 2 --------
    input  logic [4:0]   rs2_addr,
    output logic [31:0]  rs2_data,

    // -------- write port (driven from MEM/WB stage) --------
    input  logic [4:0]   rd_addr_w,
    input  logic [31:0]  write_data,
    input  logic         reg_write_w
);

    // 32 registers, 32 bits each
    logic [31:0] regs [31:0];

    // =========================================================
    // Write port - synchronous
    // x0 is never actually written (stays 0 always)
    // =========================================================
    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'h00000000;
        end
        else if (reg_write_w && (rd_addr_w != 5'd0)) begin
            regs[rd_addr_w] <= write_data;
        end
    end

    // =========================================================
    // Read ports - combinational, with write-first bypass
    // If the address being read this cycle matches the address
    // being written this same cycle, forward write_data directly
    // instead of reading the (stale, pre-clock-edge) regs[] value.
    // x0 always reads as 0, regardless of bypass.
    // =========================================================
    always_comb begin
        if (rs1_addr == 5'd0)
            rs1_data = 32'h00000000;
        else if (reg_write_w && (rs1_addr == rd_addr_w))
            rs1_data = write_data;
        else
            rs1_data = regs[rs1_addr];
    end

    always_comb begin
        if (rs2_addr == 5'd0)
            rs2_data = 32'h00000000;
        else if (reg_write_w && (rs2_addr == rd_addr_w))
            rs2_data = write_data;
        else
            rs2_data = regs[rs2_addr];
    end

endmodule