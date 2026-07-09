# RV32I-3-stage-Pipelining-RISC-V-Microprocessor-using-System-Verilog-
A 32-bit 3-stage pipelined RISC-V (RV32I) processor designed in SystemVerilog, featuring Instruction Fetch, Decode/Execute, and Memory/Writeback stages. Supports the complete RV32I base ISA with hazard detection, data forwarding, pipeline stalling, branch/jump control, and an efficient register file for reliable instruction execution.
# 3-Stage Pipelined RV32I RISC-V Processor

This project implements a **32-bit 3-stage pipelined RISC-V (RV32I) processor** designed entirely in **SystemVerilog**. The processor follows the **Instruction Fetch (IF), Decode/Execute (ID/EX), and Memory/Writeback (MEM/WB)** pipeline architecture, providing improved instruction throughput while maintaining a simple and efficient design.

The processor supports the complete **RV32I base integer instruction set**, including arithmetic, logical, immediate, load/store, branch, jump, and upper-immediate instructions. A centralized control unit decodes instructions and generates the required control signals for each pipeline stage.

The datapath consists of a **Program Counter (PC)**, **Instruction Memory**, **Register File**, **Immediate Generator**, **Arithmetic Logic Unit (ALU)**, **Data Memory**, and **Writeback logic**. The register file implements two read ports and one write port, with **x0 permanently hardwired to zero** in accordance with the RISC-V specification.

To ensure correct execution of dependent instructions, the processor incorporates **hazard detection**, **data forwarding (bypassing)**, and **pipeline stall mechanisms**. Control hazards caused by branch and jump instructions are handled through dedicated branch decision logic and program counter redirection.

The design is modular, with separate SystemVerilog modules for the datapath, control unit, ALU, register file, memories, immediate generator, multiplexers, hazard detection unit, forwarding unit, and pipeline registers. This modular architecture simplifies verification, debugging, and future extensions.

## Features

* 32-bit RISC-V processor implementing the RV32I base ISA
* 3-stage pipelined architecture (IF, ID/EX, MEM/WB)
* Complete support for arithmetic, logical, immediate, load/store, branch, jump, and upper-immediate instructions
* Hazard detection and pipeline stall logic
* Data forwarding (bypassing) to minimize pipeline stalls
* Register file with x0 permanently tied to zero
* Modular SystemVerilog implementation for readability and scalability
* Clean separation of datapath and control logic
* Designed for simulation, verification, and computer architecture education

This project demonstrates the fundamental concepts of pipelined processor design, instruction decoding, control signal generation, hazard resolution, and efficient datapath implementation while adhering to the RISC-V RV32I specification.
