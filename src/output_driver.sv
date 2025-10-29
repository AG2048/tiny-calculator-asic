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

    output logic                  o_sr_data,
    output logic                  o_sr_clk,
    output logic                  o_sr_latch
);
  /*
    Output driver module that:
      takes in a DATA_WIDTH data input, 
      converts it to 7-seg display format,
      output via shift register interface (o_sr_data, o_sr_clk, o_sr_latch).

    Input follows a valid-ready handshake protocol.
    When (i_valid && o_ready), input data is latched along with i_2s_comp bit indicating if data is in 2's complement format.
      (value is negative if i_2s_comp is high and MSB of i_data is 1)
    Data is then converted to HEX format for 7-seg display, 4-bit per digit.
      (Convert lowest 4 bits, send result out, shift right by 4 bits, repeat for NUM_7_SEG_DISPLAYS times)
      (TODO: Consider not illuminating leading zeros by checking if remaining bits are 0)
      (TODO: When data is negative the most significant digit should show '-' sign)
      (TODO: When data is negative, the conversion may be different)
      (TODO: Must flush the shift register with EMPTY before sending new data / or we can send a reset signal to the shift register first)
  */

// TODO: remove these: Temp assign all input to 0, tie all output to & _unused
logic _unused = &{clk, rst_n, i_data, i_2s_comp, i_valid};
assign o_sr_data  = _unused;
assign o_sr_clk   = _unused;
assign o_sr_latch = _unused;
assign o_ready    = _unused;

endmodule