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
  
  // Internal signal declarations
  wire [3:0] o_word_lines;
  wire [3:0] i_bit_lines;

  wire [4:0] input_value;
  wire       input_valid;
  wire       input_ready;

  wire i_add_pin;
  wire i_sub_pin;
  wire i_mul_pin;
  wire i_div_pin;
  wire i_ac_pin;
  wire i_eq_pin;
  wire i_neg_pin;

  wire i_2s_comp_mode_pin;

  wire [DATA_WIDTH-1:0] alu_input_a;
  wire [DATA_WIDTH-1:0] alu_input_b;
  wire [1:0]            alu_input_op;
  wire                  alu_input_signed; // TODO: Might be just tied to i_2s_comp_mode_pin
  wire                  alu_input_valid;
  wire                  alu_input_ready;

  wire [DATA_WIDTH-1:0] alu_output_result;
  wire                  alu_output_error;
  wire                  alu_output_valid;
  wire                  alu_output_ready;

  wire                  o_add_state_display;
  wire                  o_sub_state_display;
  wire                  o_mul_state_display;
  wire                  o_div_state_display;

  wire [DATA_WIDTH-1:0] output_value;
  wire                  output_valid;
  wire                  output_ready;
  wire                  output_2s_comp; // TODO: Might be just tied to i_2s_comp_mode_pin

  wire                  o_sr_data;
  wire                  o_sr_clk;
  wire                  o_sr_latch;

  // Assign uio pins direction and unused pins
  assign uio_oe       = 8'b00111100;          // uio[2:5] are outputs, others are inputs
  assign uio_out[7:6] = 2'b00;                // Unused output pins
  assign uio_out[1:0] = 2'b00;                // Unused output pins
  wire   _unused      = &{uio_in[5:2], ena, 1'b0}; // Prevent unused input warnings
  // Assign signals to Output Pins
  assign uo_out[3:0] = o_word_lines;
  assign uio_out[2]  = o_add_state_display;
  assign uio_out[3]  = o_sub_state_display;
  assign uio_out[4]  = o_mul_state_display;
  assign uio_out[5]  = o_div_state_display;
  assign uo_out[4]   = o_sr_data;
  assign uo_out[5]   = o_sr_clk;
  assign uo_out[6]   = o_sr_latch;
  assign uo_out[7]   = alu_output_error; // Indicate error on dedicated output pin
  // Assign Input Pins to signals
  assign i_bit_lines        = ui_in[3:0];
  assign i_add_pin          = ui_in[4];
  assign i_sub_pin          = ui_in[5];
  assign i_mul_pin          = ui_in[6];
  assign i_div_pin          = ui_in[7];
  assign i_ac_pin           = uio_in[0];
  assign i_eq_pin           = uio_in[1];
  assign i_2s_comp_mode_pin = uio_in[6];
  assign i_neg_pin          = uio_in[7];

  // Instantiate the button_reader module
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
      .i_neg_pin    (i_neg_pin),

      .o_data       (input_value),
      .o_valid      (input_valid),
      .i_ready      (input_ready)
  );

  // Instantiate the calculator core (FSM) module
  calculator_core #(
      .DATA_WIDTH(DATA_WIDTH)
  ) cc_inst (
      .clk                 (clk),
      .rst_n               (rst_n),

      .i_button_data       (input_value),
      .i_button_valid      (input_valid),
      .o_button_ready      (input_ready),
      .i_2s_comp_mode      (i_2s_comp_mode_pin),

      .o_alu_input_a       (alu_input_a),
      .o_alu_input_b       (alu_input_b),
      .o_alu_input_op      (alu_input_op),
      .o_alu_input_signed  (alu_input_signed),
      .o_alu_input_valid   (alu_input_valid),
      .i_alu_input_ready   (alu_input_ready),

      .i_alu_result        (alu_output_result),
      .i_alu_error         (alu_output_error),
      .i_alu_result_valid  (alu_output_valid),
      .o_alu_result_ready  (alu_output_ready),

      .o_add_state_display (o_add_state_display),
      .o_sub_state_display (o_sub_state_display),
      .o_mul_state_display (o_mul_state_display),
      .o_div_state_display (o_div_state_display),

      .o_display_data      (output_value),
      .o_display_2s_comp   (output_2s_comp),
      .o_display_valid     (output_valid),
      .i_display_ready     (output_ready)
  );

  // Instantiate the ALU module
  alu #(
      .DATA_WIDTH(DATA_WIDTH)
  ) alu_inst (
      .clk                (clk),
      .rst_n              (rst_n),

      .i_alu_input_a      (alu_input_a),
      .i_alu_input_b      (alu_input_b),
      .i_alu_input_op     (alu_input_op),
      .i_alu_input_signed (alu_input_signed),
      .i_alu_input_valid  (alu_input_valid),
      .o_alu_input_ready  (alu_input_ready),

      .o_alu_result       (alu_output_result),
      .o_alu_error        (alu_output_error),
      .o_alu_result_valid (alu_output_valid),
      .i_alu_result_ready (alu_output_ready)
  );

  // Instantiate the output driver (shift register) module
  output_driver #(
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_7_SEG_DISPLAYS(NUM_7_SEG_DISPLAYS)
  ) od_inst (
      .clk        (clk),
      .rst_n      (rst_n),

      .i_data     (output_value),
      .i_2s_comp  (output_2s_comp),
      .i_valid    (output_valid),
      .o_ready    (output_ready),

      .o_sr_data  (o_sr_data),
      .o_sr_clk   (o_sr_clk),
      .o_sr_latch (o_sr_latch)
  );

endmodule
