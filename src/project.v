/*
 * Copyright (c) 2025 Andy Gong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ag2048_calculator (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  // Localparam definitions
  localparam DATA_WIDTH = 16;
  localparam NUM_7_SEG_DISPLAYS = 5;

  // All output pins must be assigned. If not used, assign to 0.
  
  assign uio_out     = 0;
  assign uio_oe[7:6] = 0;
  
  // Instantiate the button_reader module
  wire [4:0] input_value;
  wire       input_valid;
  wire       input_ready;

  wire [3:0] o_word_lines;
  wire [3:0] i_bit_lines;

  wire i_ac_pin;
  wire i_add_pin;
  wire i_sub_pin;
  wire i_mul_pin;
  wire i_div_pin;
  wire i_eq_pin;

  assign uo_out[3:0] = o_word_lines;
  assign i_bit_lines = ui_in[3:0];

  assign uio_oe[5:0] = 6'b000000;
  assign i_ac_pin    = uio_in[0];
  assign i_add_pin   = uio_in[1];
  assign i_sub_pin   = uio_in[2];
  assign i_mul_pin   = uio_in[3];
  assign i_div_pin   = uio_in[4];
  assign i_eq_pin    = uio_in[5];

  button_reader br_inst (
      .clk          (clk),
      .rst_n        (rst_n),

      .o_word_lines (o_word_lines),
      .i_bit_lines  (i_bit_lines),

      .i_ac_pin     (i_ac_pin),
      .i_add_pin    (i_add_pin),
      .i_sub_pin    (i_sub_pin),
      .i_mul_pin    (i_mul_pin),
      .i_div_pin    (i_div_pin),
      .i_eq_pin     (i_eq_pin),

      .o_data       (input_value),
      .o_valid      (input_valid),
      .i_ready      (input_ready)
  );

  // Instantiate the calculator core (FSM) module
  // TODO
  assign input_ready = ui_in[7]; // Always not ready to accept input // Placeholder to not optimize away

  calculator_core cc_inst #(
      .DATA_WIDTH(DATA_WIDTH)
  ) (
      .clk          (clk),
      .rst_n        (rst_n),

      
  );

  // Instantiate the ALU module
  // TODO

  alu alu_inst #(
      .DATA_WIDTH(DATA_WIDTH)
  ) (
      .clk          (clk),
      .rst_n        (rst_n),

      
  );

  // Instantiate the output driver (shift register) module
  // TODO

  output_driver od_inst #(
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_7_SEG_DISPLAYS(NUM_7_SEG_DISPLAYS)
  ) (
      .clk          (clk),
      .rst_n        (rst_n),

      
  );

  // List all unused inputs to prevent warnings
  assign uo_out[7:4] = &{input_value, input_valid}; // Prevent unused output warnings, and don't optimize away
  wire _unused = &{ena, ui_in[6:4], uio_in[7:6], input_value, input_valid, 1'b0};

endmodule
