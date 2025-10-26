/*
 * Copyright (c) 2025 Andy Gong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module calculator_core #(
    parameter DATA_WIDTH = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,
    
    input  logic [4:0]            i_button_data,
    input  logic                  i_button_valid,
    output logic                  o_button_ready,
    input  logic                  i_2s_comp_mode,     // Indicates if calculations and displays are in 2's complement mode

    output logic [DATA_WIDTH-1:0] o_alu_input_a,
    output logic [DATA_WIDTH-1:0] o_alu_input_b,
    output logic [1:0]            o_alu_input_op,     // 00: ADD, 01: SUB, 10: MUL, 11: DIV
    output logic                  o_alu_input_signed, // 1: signed (2's comp), 0: unsigned (mostly for MUL and DIV)
    output logic                  o_alu_input_valid,
    input  logic                  i_alu_input_ready,

    input  logic [DATA_WIDTH-1:0] i_alu_result,
    input  logic                  i_alu_error,
    input  logic                  i_alu_result_valid,
    output logic                  o_alu_result_ready,

    output logic                  o_add_state_display,
    output logic                  o_sub_state_display,
    output logic                  o_mul_state_display,
    output logic                  o_div_state_display,

    output logic [DATA_WIDTH-1:0] o_display_data,
    output logic                  o_display_2s_comp,
    output logic                  o_display_valid,
    input  logic                  i_display_ready,
    input  logic                  i_display_done
);


endmodule