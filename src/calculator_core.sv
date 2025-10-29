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
  // Temp assign all input to 0, tie all output to & _unused TODO: remove them
  logic _unused = &{clk, rst_n, i_button_data, i_button_valid, i_2s_comp_mode, i_alu_result, i_alu_error, i_alu_result_valid, i_display_ready, i_display_done, i_alu_input_ready};
  assign {o_alu_input_a, o_alu_input_b, o_alu_input_op, o_alu_input_signed, o_alu_input_valid, o_alu_result_ready, o_add_state_display, o_sub_state_display, o_mul_state_display, o_div_state_display, o_display_data, o_display_2s_comp, o_display_valid, o_button_ready} = '{default: _unused};
  
  // Enumerate FSM states
  typedef enum logic [4:0] {
    AC,
    WAIT_FIRST_INPUT,
    FIRST_INPUT_NUMBER,
    DISPLAY_AFTER_FIRST_INPUT,
    WAIT_DISPLAY_DONE_AFTER_FIRST_INPUT,
    FIRST_INPUT_OP,
    WAIT_SECOND_INPUT_BEFORE_VALUE,
    COPY_A_TO_B,
    SECOND_INPUT_NUMBER,
    DISPLAY_AFTER_SECOND_INPUT,
    WAIT_DISPLAY_DONE_AFTER_SECOND_INPUT,
    WAIT_SECOND_INPUT_AFTER_VALUE,
    SECOND_INPUT_OP_CALCULATE,
    DISPLAY_AFTER_SECOND_OP,
    WAIT_DISPLAY_DONE_AFTER_SECOND_OP,
    EQUAL_AFTER_SECOND_VALUE,
    DISPLAY_AFTER_EQUAL,
    WAIT_DISPLAY_DONE_AFTER_EQUAL,
    WAIT_INPUT_AFTER_EQUAL,
    CLEAR_AFTER_EQUAL,
    ERROR
  } fsm_state_t;

  fsm_state_t current_state;

  // FSM state transition
  // State transition
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= AC;
    end else begin
      case (current_state)
        AC:
          begin
            current_state <= WAIT_FIRST_INPUT;
          end
        WAIT_FIRST_INPUT:
          begin
            if (i_button_valid && o_button_ready) begin
              if (i_button_data[4] == 1'b0) begin
                // Number input
                current_state <= FIRST_INPUT_NUMBER;
              end else begin
                if (i_button_data == 5'b10101) begin
                  // AC pressed, move to AC state
                  current_state <= AC;
                end else if (i_button_data != 5'b10100) begin
                  // For all buttons other than EQ, move to FIRST_INPUT_OP
                  // TODO: NEG button may require some special flags
                  current_state <= FIRST_INPUT_OP;
                end
              end
            end
          end
        FIRST_INPUT_NUMBER:
          begin
            // Value should be loaded into reg A in 1 cycle
            current_state <= DISPLAY_AFTER_FIRST_INPUT;
          end
        DISPLAY_AFTER_FIRST_INPUT:
          begin
            // Wait for value to be sent to display
            if (o_display_valid && i_display_ready) begin
              current_state <= WAIT_DISPLAY_DONE_AFTER_FIRST_INPUT;
            end
          end
        WAIT_DISPLAY_DONE_AFTER_FIRST_INPUT:
          begin
            // Wait for display to be done
            if (i_display_done) begin
              current_state <= WAIT_FIRST_INPUT;
            end
          end
      endcase
    end
  end

endmodule