/*
 * Copyright (c) 2025 Andy Gong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module output_driver #(
    parameter DATA_WIDTH = 16,
    parameter NUM_7_SEG_DISPLAYS = 5
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [DATA_WIDTH-1:0] i_data,
    input  logic                  i_2s_comp,  // Indicates if i_data is in 2's complement format
    input  logic                  i_valid,
    output logic                  o_ready,
    output logic                  o_done,     // Low when data is being shifted out

    output logic                  o_sr_data,
    output logic                  o_sr_clk,
    output logic                  o_sr_latch
);


endmodule