// =============================================================
// riscv_trace_tb.sv
// Keil µVision-style register window testbench
//
// After every non-NOP instruction retires through MEM/WB, prints:
//  - Cycle number, PC of completing instruction
//  - Decoded assembly mnemonic
//  - All 32 registers in a 4-column grid (changed register marked *)
//  - Data memory change if it was a store
//  - Load-use stall notification if the stall unit fires
// =============================================================

`timescale 1ns / 1ps

module riscv_trace_tb;

    // =========================================================
    // Clock + reset
    // =========================================================
    logic clk, reset;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =========================================================
    // DUT
    // =========================================================
    riscv_top dut (.clk(clk), .reset(reset));

    // =========================================================
    // Shadow pipeline: track the raw instruction word as it
    // flows from IF/DE -> DE/MEM so we can decode what just
    // retired in MEM/WB each cycle.
    // =========================================================
    logic [31:0] shadow_instr_wb;   // instruction retiring this cycle
    logic [31:0] shadow_pc_wb;      // its PC

    always_ff @(posedge clk) begin
        if (reset) begin
            shadow_instr_wb <= 32'h00000013;
            shadow_pc_wb    <= 32'h00000000;
        end else begin
            shadow_instr_wb <= dut.ifde_instr;   // one cycle behind = in MEM/WB
            shadow_pc_wb    <= dut.ifde_pc;
        end
    end

    // =========================================================
    // Register snapshot for diff (which reg changed this cycle?)
    // =========================================================
    logic [31:0] prev_regs [31:0];
    integer      cycle_count;

    // =========================================================
    // Instruction decode helpers
    // =========================================================
    // Extract fields from a 32-bit instruction word
    function automatic logic [6:0] get_opcode(input logic [31:0] w); return w[6:0];   endfunction
    function automatic logic [4:0] get_rd    (input logic [31:0] w); return w[11:7];  endfunction
    function automatic logic [2:0] get_funct3(input logic [31:0] w); return w[14:12]; endfunction
    function automatic logic [4:0] get_rs1   (input logic [31:0] w); return w[19:15]; endfunction
    function automatic logic [4:0] get_rs2   (input logic [31:0] w); return w[24:20]; endfunction
    function automatic logic [6:0] get_funct7(input logic [31:0] w); return w[31:25]; endfunction

    function automatic logic signed [31:0] imm_i(input logic [31:0] w);
        return $signed({{20{w[31]}}, w[31:20]});
    endfunction
    function automatic logic signed [31:0] imm_s(input logic [31:0] w);
        return $signed({{20{w[31]}}, w[31:25], w[11:7]});
    endfunction
    function automatic logic signed [31:0] imm_b(input logic [31:0] w);
        return $signed({{19{w[31]}}, w[31], w[7], w[30:25], w[11:8], 1'b0});
    endfunction
    function automatic logic [31:0] imm_u(input logic [31:0] w);
        return {w[31:12], 12'b0};
    endfunction
    function automatic logic signed [31:0] imm_j(input logic [31:0] w);
        return $signed({{11{w[31]}}, w[31], w[19:12], w[20], w[30:21], 1'b0});
    endfunction

    // Return register name string
    function automatic string rname(input logic [4:0] r);
        case (r)
            5'd0:  return "x0 (zero)";  5'd1:  return "x1  (ra)";
            5'd2:  return "x2  (sp)";   5'd3:  return "x3  (gp)";
            5'd4:  return "x4  (tp)";   5'd5:  return "x5  (t0)";
            5'd6:  return "x6  (t1)";   5'd7:  return "x7  (t2)";
            5'd8:  return "x8  (s0)";   5'd9:  return "x9  (s1)";
            5'd10: return "x10 (a0)";   5'd11: return "x11 (a1)";
            5'd12: return "x12 (a2)";   5'd13: return "x13 (a3)";
            5'd14: return "x14 (a4)";   5'd15: return "x15 (a5)";
            5'd16: return "x16 (a6)";   5'd17: return "x17 (a7)";
            5'd18: return "x18 (s2)";   5'd19: return "x19 (s3)";
            5'd20: return "x20 (s4)";   5'd21: return "x21 (s5)";
            5'd22: return "x22 (s6)";   5'd23: return "x23 (s7)";
            5'd24: return "x24 (s8)";   5'd25: return "x25 (s9)";
            5'd26: return "x26(s10)";   5'd27: return "x27(s11)";
            5'd28: return "x28 (t3)";   5'd29: return "x29 (t4)";
            5'd30: return "x30 (t5)";   5'd31: return "x31 (t6)";
            default: return "x??";
        endcase
    endfunction

    function automatic string rshort(input logic [4:0] r);
        case (r)
            5'd0:return "x0 "; 5'd1: return "x1 "; 5'd2: return "x2 ";
            5'd3:return "x3 "; 5'd4: return "x4 "; 5'd5: return "x5 ";
            5'd6:return "x6 "; 5'd7: return "x7 "; 5'd8: return "x8 ";
            5'd9:return "x9 "; 5'd10:return "x10"; 5'd11:return "x11";
            5'd12:return "x12";5'd13:return "x13"; 5'd14:return "x14";
            5'd15:return "x15";5'd16:return "x16"; 5'd17:return "x17";
            5'd18:return "x18";5'd19:return "x19"; 5'd20:return "x20";
            5'd21:return "x21";5'd22:return "x22"; 5'd23:return "x23";
            5'd24:return "x24";5'd25:return "x25"; 5'd26:return "x26";
            5'd27:return "x27";5'd28:return "x28"; 5'd29:return "x29";
            5'd30:return "x30";5'd31:return "x31";
            default:return "x??";
        endcase
    endfunction

    // Decode instruction to mnemonic string
    function automatic string decode_instr(
        input logic [31:0] w,
        input logic [31:0] pc
    );
        logic [6:0] opc;  logic [4:0] rd, rs1, rs2;
        logic [2:0] f3;   logic [6:0] f7;
        string s;
        opc = get_opcode(w); rd = get_rd(w); f3 = get_funct3(w);
        rs1 = get_rs1(w);    rs2 = get_rs2(w); f7 = get_funct7(w);

        case (opc)
            7'b0010011: begin // I-type ALU
                case (f3)
                    3'b000: $sformat(s, "addi  %s, %s, %0d",
                                rshort(rd), rshort(rs1), $signed(imm_i(w)));
                    3'b001: $sformat(s, "slli  %s, %s, %0d",
                                rshort(rd), rshort(rs1), imm_i(w) & 32'h1F);
                    3'b010: $sformat(s, "slti  %s, %s, %0d",
                                rshort(rd), rshort(rs1), $signed(imm_i(w)));
                    3'b011: $sformat(s, "sltiu %s, %s, %0d",
                                rshort(rd), rshort(rs1), $signed(imm_i(w)));
                    3'b100: $sformat(s, "xori  %s, %s, %0d",
                                rshort(rd), rshort(rs1), $signed(imm_i(w)));
                    3'b101: begin
                        if (f7[5]) $sformat(s, "srai  %s, %s, %0d",
                                    rshort(rd), rshort(rs1), imm_i(w) & 32'h1F);
                        else       $sformat(s, "srli  %s, %s, %0d",
                                    rshort(rd), rshort(rs1), imm_i(w) & 32'h1F);
                    end
                    3'b110: $sformat(s, "ori   %s, %s, %0d",
                                rshort(rd), rshort(rs1), $signed(imm_i(w)));
                    3'b111: $sformat(s, "andi  %s, %s, %0d",
                                rshort(rd), rshort(rs1), $signed(imm_i(w)));
                    default: s = "??I";
                endcase
            end
            7'b0110011: begin // R-type
                case ({f7[5], f3})
                    4'b0000: $sformat(s, "add   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b1000: $sformat(s, "sub   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0001: $sformat(s, "sll   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0010: $sformat(s, "slt   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0011: $sformat(s, "sltu  %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0100: $sformat(s, "xor   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0110: $sformat(s, "srl   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b1110: $sformat(s, "sra   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0111: $sformat(s, "and   %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    4'b0101: $sformat(s, "or    %s, %s, %s", rshort(rd), rshort(rs1), rshort(rs2));
                    default: s = "??R";
                endcase
            end
            7'b0000011: begin // Load
                case (f3)
                    3'b000: $sformat(s, "lb    %s, %0d(%s)", rshort(rd), $signed(imm_i(w)), rshort(rs1));
                    3'b001: $sformat(s, "lh    %s, %0d(%s)", rshort(rd), $signed(imm_i(w)), rshort(rs1));
                    3'b010: $sformat(s, "lw    %s, %0d(%s)", rshort(rd), $signed(imm_i(w)), rshort(rs1));
                    3'b100: $sformat(s, "lbu   %s, %0d(%s)", rshort(rd), $signed(imm_i(w)), rshort(rs1));
                    3'b101: $sformat(s, "lhu   %s, %0d(%s)", rshort(rd), $signed(imm_i(w)), rshort(rs1));
                    default: s = "??L";
                endcase
            end
            7'b0100011: begin // Store
                case (f3)
                    3'b000: $sformat(s, "sb    %s, %0d(%s)", rshort(rs2), $signed(imm_s(w)), rshort(rs1));
                    3'b001: $sformat(s, "sh    %s, %0d(%s)", rshort(rs2), $signed(imm_s(w)), rshort(rs1));
                    3'b010: $sformat(s, "sw    %s, %0d(%s)", rshort(rs2), $signed(imm_s(w)), rshort(rs1));
                    default: s = "??S";
                endcase
            end
            7'b1100011: begin // Branch
                case (f3)
                    3'b000: $sformat(s, "beq   %s, %s, 0x%08h",
                                rshort(rs1), rshort(rs2), pc + imm_b(w));
                    3'b001: $sformat(s, "bne   %s, %s, 0x%08h",
                                rshort(rs1), rshort(rs2), pc + imm_b(w));
                    3'b100: $sformat(s, "blt   %s, %s, 0x%08h",
                                rshort(rs1), rshort(rs2), pc + imm_b(w));
                    3'b101: $sformat(s, "bge   %s, %s, 0x%08h",
                                rshort(rs1), rshort(rs2), pc + imm_b(w));
                    default: s = "??B";
                endcase
            end
            7'b1101111: $sformat(s, "jal   %s, 0x%08h", rshort(rd), pc + imm_j(w));
            7'b1100111: $sformat(s, "jalr  %s, %s, %0d", rshort(rd), rshort(rs1), $signed(imm_i(w)));
            7'b0110111: $sformat(s, "lui   %s, 0x%05h", rshort(rd), w[31:12]);
            7'b0010111: $sformat(s, "auipc %s, 0x%05h", rshort(rd), w[31:12]);
            default:    $sformat(s, "???   0x%08h", w);
        endcase
        return s;
    endfunction

    // Is this instruction a NOP (addi x0, x0, 0)?
    function automatic logic is_nop(input logic [31:0] w);
        return (w == 32'h00000013);
    endfunction

    // Is this a branch instruction?
    function automatic logic is_branch(input logic [31:0] w);
        return (w[6:0] == 7'b1100011);
    endfunction

    // Is this a store instruction?
    function automatic logic is_store(input logic [31:0] w);
        return (w[6:0] == 7'b0100011);
    endfunction

    // =========================================================
    // Print the register file in a 4-column Keil-style grid
    // =========================================================
    task automatic print_registers(input logic [4:0] changed_rd, input bit did_write);
        string marker;
        logic [31:0] val;
        $display("  +---------+--------------------+---------+--------------------+---------+--------------------+---------+--------------------+");
        $display("  |  Reg    |  Hex       Dec     |  Reg    |  Hex       Dec     |  Reg    |  Hex       Dec     |  Reg    |  Hex       Dec     |");
        $display("  +---------+--------------------+---------+--------------------+---------+--------------------+---------+--------------------+");
        for (int row = 0; row < 8; row++) begin
            string line;
            line = "  |";
            for (int col = 0; col < 4; col++) begin
                int idx;
                string flag, hexval, decval, reg_label;
                idx = row + col*8;
                val = dut.u_regfile.regs[idx];
                flag = (did_write && idx == int'(changed_rd) && idx != 0) ? "*" : " ";
                $sformat(reg_label, "%s x%-2d  ", flag, idx);
                $sformat(hexval,    "0x%08h", val);
                $sformat(decval,    "%11d", $signed(val));
                line = {line, " ", reg_label, " ", hexval, " ", decval, " |"};
            end
            $display("%s", line);
        end
        $display("  +---------+--------------------+---------+--------------------+---------+--------------------+---------+--------------------+");
    endtask

    // =========================================================
    // Print data memory word at an address (for store/load trace)
    // =========================================================
    task automatic print_dmem_word(input logic [31:0] addr);
        logic [31:0] word;
        word = {dut.u_dmem.mem[addr+3], dut.u_dmem.mem[addr+2],
                dut.u_dmem.mem[addr+1], dut.u_dmem.mem[addr]};
        $display("  | DMEM[0x%08h] = 0x%08h  (%0d signed, %0d unsigned)",
                 addr, word, $signed(word), word);
    endtask

    // =========================================================
    // Stall detection
    // =========================================================
    always @(posedge clk) begin
        if (!reset && dut.stall)
            $display("  [STALL] Load-use hazard detected at cycle %0d — pipeline frozen for 1 cycle", cycle_count);
    end

    // =========================================================
    // Branch/flush detection
    // =========================================================
    always @(posedge clk) begin
        if (!reset && dut.branch_flush)
            $display("  [FLUSH] Branch/jump taken at cycle %0d — flushing wrongly-fetched instruction", cycle_count);
    end

    // =========================================================
    // Main retire monitor
    // =========================================================
    logic [31:0] instr_count;
    initial instr_count = 0;

    always @(posedge clk) begin
        if (!reset) begin
            logic [31:0] w;
            logic [4:0]  rd;
            logic [6:0]  opc;
            string       mnemonic;
            bit          printed;

            w   = shadow_instr_wb;
            rd  = get_rd(w);
            opc = get_opcode(w);

            // Skip NOPs — they're pipeline filler and clutter the output
            if (!is_nop(w)) begin
                instr_count = instr_count + 1;
                mnemonic = decode_instr(w, shadow_pc_wb);

                $display("");
                $display("----------------------------------------------------------------------------------");
                $display("║  INSTR #%-3d   Cycle: %-4d   PC: 0x%08h                                         ║",
                          instr_count, cycle_count, shadow_pc_wb);
                $display("----------------------------------------------------------------------------------");
                
              $display("║  ASM  :  %-76s║", mnemonic);

                
              // Writeback effect line
                if (is_store(w)) begin
                    logic [31:0] eff_addr;
                    eff_addr = dut.mem_alu_result;
                    $display("║  EFFECT: Store to DMEM[0x%08h]                                              ║", eff_addr);
                end else if (opc == 7'b1100011) begin
                    // branch - show taken/not-taken
                    if (dut.pc_src_final)
                        $display("║  EFFECT: Branch TAKEN  -> PC jumps to 0x%08h                               ║", dut.branch_target_final);
                    else
                        $display("║  EFFECT: Branch NOT TAKEN  (falls through)                                     ║");
                end else if (dut.mem_reg_write && rd != 0) begin
                    $display("║  EFFECT: %s (%s) <= 0x%08h  (%0d)                             ║",
                              rname(rd), rshort(rd), dut.wb_write_data, $signed(dut.wb_write_data));
                end else begin
                    $display("║  EFFECT: No register write                                                         ║");
                end
                $display("----------------------------------------------------------------------------------");
                $display("║  REGISTER FILE (* = changed this instruction)                                       ║");
                $display("----------------------------------------------------------------------------------");

                print_registers(rd, dut.mem_reg_write && (rd != 0));

                // For stores, show the affected memory word
                if (is_store(w)) begin
                    logic [31:0] eff_addr;
                    eff_addr = {dut.mem_alu_result[31:2], 2'b00}; // word align
                  $display("  ---DATA MEMORY ----------------------------------------------------------------------------------");
                    print_dmem_word(eff_addr);
                  $display("----------------------------------------------------------------------------------------------");
                end
            end
        end
    end

    // =========================================================
    // Cycle counter
    // =========================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) cycle_count <= 0;
        else       cycle_count <= cycle_count + 1;
    end

    // =========================================================
    // Test sequence
    // =========================================================
    initial begin
      $display("----------------------------------------------------------------------------------");
      $display("-        3-Stage RISC-V RV32I Processor — Keil-Style Register Trace                  -");
      $display("-        All 49 corner-case instructions monitored                                    -");
      $display("----------------------------------------------------------------------------------");

        reset = 1'b1;
        repeat(3) @(posedge clk);
        reset = 1'b0;
        $display("  [RESET released at t=%0t]", $time);

        // 136 program words + pipeline drain + branch/jal stall margin = ~350 cycles
        repeat(350) @(posedge clk);

        $display("");
        $display("----------------------------------------------------------------------------------");
        $display("║  SIMULATION COMPLETE — %0d instructions retired                                 ║", instr_count);
        $display("----------------------------------------------------------------------------------");
        $finish;
    end

    // Safety timeout
    initial begin
        #50000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule