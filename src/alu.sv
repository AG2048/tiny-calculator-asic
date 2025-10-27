/*
 * Copyright (c) 2025 Andy Gong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module alu #(
    parameter DATA_WIDTH = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [DATA_WIDTH-1:0] i_alu_input_a,
    input  logic [DATA_WIDTH-1:0] i_alu_input_b,
    input  logic [1:0]            i_alu_input_op,     // 00: ADD, 01: SUB, 10: MUL, 11: DIV
    input  logic                  i_alu_input_signed, // 1: signed (2's comp), 0: unsigned (mostly for MUL and DIV)
    input  logic                  i_alu_input_valid,
    output logic                  o_alu_input_ready,
    
    output logic [DATA_WIDTH-1:0] o_alu_result,
    output logic                  o_alu_error,        // 1: error (e.g., division by zero)
    output logic                  o_alu_result_valid,
    input  logic                  i_alu_result_ready
);
// Temp assign all input to 0, tie all output to & _unused
assign {o_alu_result, o_alu_result_valid, o_alu_input_ready, o_alu_error} = '0;
logic _unused = &{clk, rst_n, i_alu_input_a, i_alu_input_b, i_alu_input_op, i_alu_input_signed, i_alu_input_valid, i_alu_result_ready};

endmodule