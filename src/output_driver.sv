/*
 * Copyright (c) 2025 Andy Gong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module output_driver #(
    parameter DATA_WIDTH = 16,
    parameter NUM_7_SEG_DISPLAYS = 5
)(
    input  wire                   clk,            // clock
    input  wire                   rst_n,          // reset_n - low to reset
    // Add other ports as needed
);


endmodule