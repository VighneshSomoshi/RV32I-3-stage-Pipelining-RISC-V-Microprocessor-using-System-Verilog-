// =============================================================
// riscv_top.sv
// Top-level 3-stage RISC-V (RV32I) pipeline:
//   Stage 1: IF        (if_stage, imem)
//   Stage 2: DE/EX      (id_stage, regfile read, alu_control, alu, branch_unit)
//   Stage 3: MEM/WB     (dmem, wb_mux, regfile write)
//
// Hazard handling: stall-only (load-use), no forwarding unit -
// regfile uses write-first same-cycle bypass internally instead.
//
// FIXES APPLIED (vs original version):
//   1. stall_unit was wired from ifde_instr (the instruction
//      CURRENTLY in ID/EX, the load itself), comparing it against
//      its own rs1/rs2 -- effectively a no-op check. It must
//      instead compare against if_instr_out (the instruction about
//      to enter ID/EX NEXT cycle, i.e. the one that might actually
//      depend on the load's result).
//   2. de_mem_flush was tied directly to stall. That squashed the
//      load instruction itself out of the pipeline every cycle
//      stall was high, so the load never reached MEM/WB and never
//      produced a result -- combined with stall never being able
//      to clear (since the frozen IF/DE instruction never changes),
//      this caused a permanent deadlock. Fixed by (a) never
//      flushing de_mem_reg on a stall -- the load must be allowed
//      to proceed into DE/MEM normally, and (b) turning stall into
//      a one-cycle pulse (qualified by stall_prev) instead of a
//      level signal, since one bubble cycle is sufficient for the
//      regfile's write-first bypass to resolve the hazard.
// =============================================================

`include "if_stage.sv"
`include "imem.sv"
`include "if_de_reg.sv"
`include "id_stage.sv"
`include "regfile.sv"
`include "alu_control.sv"
`include "alu.sv"
`include "branch_unit.sv"
`include "stall_unit.sv"
`include "de_mem_reg.sv"
`include "dmem.sv"
`include "wb_mux.sv"

module riscv_top (
    input  logic clk,
    input  logic reset
);

    // =========================================================
    // Stage 1: IF
    // =========================================================
    logic [31:0] if_pc, if_pc_next, if_instr_out;
    logic [31:0] imem_instr;

    logic        pc_src_final;
    logic [31:0] branch_target_final;

    if_stage u_if_stage (
        .clk            (clk),
        .reset          (reset),
        .instr_in       (imem_instr),
        .pc_src         (pc_src_final),
        .branch_target  (branch_target_final),
        .pc             (if_pc),
        .pc_next        (if_pc_next),
        .instr_out      (if_instr_out)
    );

    imem u_imem (
        .addr   (if_pc),
        .instr  (imem_instr)
    );

    // =========================================================
    // IF/DE pipeline register
    // =========================================================
    logic stall;          // load-use hazard, one-cycle pulse, from stall logic below
    logic branch_flush;   // = pc_src_branch (branch/jump taken), squashes wrongly-fetched instr

    logic [31:0] ifde_instr, ifde_pc, ifde_pc_next;

    if_de_reg u_if_de_reg (
        .clk          (clk),
        .reset        (reset),
        .stall        (stall),
        .flush        (branch_flush),
        .instr_in     (if_instr_out),
        .pc_in        (if_pc),
        .pc_next_in   (if_pc_next),
        .instr_out    (ifde_instr),
        .pc_out       (ifde_pc),
        .pc_next_out  (ifde_pc_next)
    );

    // =========================================================
    // Stage 2: DE/EX
    // =========================================================
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [6:0]  id_opcode;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [31:0] id_imm_ext;
    logic [31:0] id_pc_out, id_pc_next_out;
    logic        id_reg_write, id_alu_src, id_mem_read, id_mem_write;
    logic        id_result_src, id_branch, id_jump;
    logic [3:0]  id_alu_op_cat;

    id_stage u_id_stage (
        .clk          (clk),
        .reset        (reset),
        .instr_in     (ifde_instr),
        .pc_in        (ifde_pc),
        .pc_next_in   (ifde_pc_next),
        .rs1_addr     (id_rs1_addr),
        .rs2_addr     (id_rs2_addr),
        .rd_addr      (id_rd_addr),
        .opcode       (id_opcode),
        .funct3       (id_funct3),
        .funct7       (id_funct7),
        .imm_ext      (id_imm_ext),
        .pc_out       (id_pc_out),
        .pc_next_out  (id_pc_next_out),
        .reg_write    (id_reg_write),
        .alu_src      (id_alu_src),
        .alu_op       (id_alu_op_cat),
        .mem_read     (id_mem_read),
        .mem_write    (id_mem_write),
        .result_src   (id_result_src),
        .branch       (id_branch),
        .jump         (id_jump)
    );

    // -------- regfile (read here, write driven from MEM/WB below) --------
    logic [31:0] rf_rs1_data, rf_rs2_data;
    logic [4:0]  wb_rd_addr_w;
    logic [31:0] wb_write_data;
    logic        wb_reg_write_w;

    regfile u_regfile (
        .clk          (clk),
        .reset        (reset),
        .rs1_addr     (id_rs1_addr),
        .rs1_data     (rf_rs1_data),
        .rs2_addr     (id_rs2_addr),
        .rs2_data     (rf_rs2_data),
        .rd_addr_w    (wb_rd_addr_w),
        .write_data   (wb_write_data),
        .reg_write_w  (wb_reg_write_w)
    );

    // -------- ALU control --------
    localparam logic [6:0] OPC_RTYPE = 7'b0110011;
    localparam logic [6:0] OPC_LUI   = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC = 7'b0010111;

    logic [3:0] alu_op_final;
    logic       is_rtype;
    assign is_rtype = (id_opcode == OPC_RTYPE);

    alu_control u_alu_control (
        .alu_op_cat (id_alu_op_cat),
        .funct3     (id_funct3),
        .funct7     (id_funct7),
        .is_rtype   (is_rtype),
        .alu_op     (alu_op_final)
    );

    // -------- ALU operand muxes --------
    logic [31:0] alu_operand_a, alu_operand_b;

    always_comb begin
        if (id_opcode == OPC_LUI)
            alu_operand_a = 32'h00000000;
        else if (id_opcode == OPC_AUIPC)
            alu_operand_a = id_pc_out;
        else
            alu_operand_a = rf_rs1_data;
    end

    assign alu_operand_b = id_alu_src ? id_imm_ext : rf_rs2_data;

    logic [31:0] alu_result;
    logic        alu_zero;

    alu u_alu (
        .a       (alu_operand_a),
        .b       (alu_operand_b),
        .alu_op  (alu_op_final),
        .result  (alu_result),
        .zero    (alu_zero)
    );

    // -------- branch resolution --------
    logic [31:0] branch_target_computed;
    logic        pc_src_branch;

    branch_unit u_branch_unit (
        .pc            (id_pc_out),
        .imm_ext       (id_imm_ext),
        .alu_result    (alu_result),
        .alu_zero      (alu_zero),
        .funct3        (id_funct3),
        .branch        (id_branch),
        .jump          (id_jump),
        .opcode        (id_opcode),
        .branch_target (branch_target_computed),
        .pc_src        (pc_src_branch)
    );

    // -------- stall unit (load-use hazard) --------
    // FIX 1: compare the load currently in ID/EX (id_rd_addr) against
    // the instruction about to enter ID/EX NEXT cycle (if_instr_out),
    // not against the load's own rs1/rs2 fields (which is what
    // ifde_instr would give, since ifde_instr == the instruction
    // id_stage is decoding this same cycle).
    logic [4:0] next_rs1_addr, next_rs2_addr;
    assign next_rs1_addr = if_instr_out[19:15];
    assign next_rs2_addr = if_instr_out[24:20];

    logic hazard_raw;

    stall_unit u_stall_unit (
        .id_mem_read  (id_mem_read),
        .id_rd_addr   (id_rd_addr),
        .if_rs1_addr  (next_rs1_addr),
        .if_rs2_addr  (next_rs2_addr),
        .stall        (hazard_raw)
    );

    // FIX 2: turn the raw hazard condition into (at most) a one-cycle
    // stall per offending load, instead of either:
    //   (a) a raw level signal -- which never clears, since while IF/DE
    //       is frozen, id_pc_out/id_rd_addr/if_instr_out are all frozen
    //       too, so hazard_raw stays asserted forever (deadlock); or
    //   (b) a blind "previous cycle" gate -- which incorrectly silences
    //       a genuinely NEW hazard that happens to follow immediately
    //       after a previous stall resolves (e.g. back-to-back
    //       load-use hazards).
    //
    // Instead, remember the PC of the instruction we last stalled FOR
    // (id_pc_out at the moment stall fired). hazard_raw caused by that
    // same still-frozen instruction is suppressed -- it's already been
    // handled; one bubble cycle is enough for the regfile's write-first
    // bypass to resolve it. Once IF/DE actually advances and a
    // *different* instruction reaches ID/EX, id_pc_out changes, so a
    // fresh genuine hazard is free to stall again.
    logic [31:0] stalled_for_pc;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            stalled_for_pc <= 32'hFFFFFFFF;  // sentinel: nothing stalled for yet
        else if (stall)
            stalled_for_pc <= id_pc_out;
    end

    assign stall = hazard_raw && (id_pc_out != stalled_for_pc);

    // -------- final PC control: stall takes priority over branch --------
    assign pc_src_final        = stall ? 1'b1   : pc_src_branch;
    assign branch_target_final = stall ? if_pc  : branch_target_computed;
    assign branch_flush        = pc_src_branch;  // only flush on real branch/jump, not stall-refetch

    // =========================================================
    // DE/MEM pipeline register
    // =========================================================
    logic [31:0] mem_alu_result, mem_rs2_data, mem_pc_next, mem_imm_ext;
    logic [4:0]  mem_rd_addr;
    logic [2:0]  mem_funct3;
    logic [6:0]  mem_opcode;
    logic        mem_reg_write, mem_mem_read, mem_mem_write, mem_result_src, mem_jump;

    // FIX 2 (cont.): the load instruction sitting in ID/EX during the
    // stall cycle MUST be allowed to proceed into DE/MEM normally. It
    // must NOT be flushed -- if it is, it can never complete and the
    // load-use hazard can never actually resolve (this was the cause
    // of the permanent deadlock).
    logic de_mem_flush;
    assign de_mem_flush = 1'b0;

    de_mem_reg u_de_mem_reg (
        .clk             (clk),
        .reset           (reset),
        .flush           (de_mem_flush),
        .alu_result_in   (alu_result),
        .rs2_data_in     (rf_rs2_data),
        .rd_addr_in      (id_rd_addr),
        .pc_next_in      (id_pc_next_out),
        .imm_ext_in      (id_imm_ext),
        .funct3_in       (id_funct3),
        .reg_write_in    (id_reg_write),
        .mem_read_in     (id_mem_read),
        .mem_write_in    (id_mem_write),
        .result_src_in   (id_result_src),
        .jump_in         (id_jump),
        .opcode_in       (id_opcode),
        .alu_result_out  (mem_alu_result),
        .rs2_data_out    (mem_rs2_data),
        .rd_addr_out     (mem_rd_addr),
        .pc_next_out     (mem_pc_next),
        .imm_ext_out     (mem_imm_ext),
        .funct3_out      (mem_funct3),
        .reg_write_out   (mem_reg_write),
        .mem_read_out    (mem_mem_read),
        .mem_write_out   (mem_mem_write),
        .result_src_out  (mem_result_src),
        .jump_out        (mem_jump),
        .opcode_out      (mem_opcode)
    );

    // =========================================================
    // Stage 3: MEM/WB
    // =========================================================
    logic [31:0] dmem_read_data;

    dmem u_dmem (
        .clk         (clk),
        .reset       (reset),
        .addr        (mem_alu_result),
        .write_data  (mem_rs2_data),
        .mem_read    (mem_mem_read),
        .mem_write   (mem_mem_write),
        .funct3      (mem_funct3),
        .read_data   (dmem_read_data)
    );

    wb_mux u_wb_mux (
        .alu_result     (mem_alu_result),
        .mem_read_data  (dmem_read_data),
        .pc_next        (mem_pc_next),
        .imm_ext        (mem_imm_ext),
        .result_src     (mem_result_src),
        .jump           (mem_jump),
        .opcode         (mem_opcode),
        .write_data     (wb_write_data)
    );

    assign wb_rd_addr_w   = mem_rd_addr;
    assign wb_reg_write_w = mem_reg_write;

endmodule
