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
    input  logic                  i_display_ready
);
  /*
    Calculator core module that implements the main FSM and data path for the calculator.

    TODO: add docs
  */

  // FSM states
  typedef enum logic [4:0] {
    AC,                                    // Pressed AC from any WAIT_INPUT state: clear all registers and flags, go to DISPLAY_AFTER_AC
    DISPLAY_AFTER_AC,                      // Display cleared reg A value (0), and return to WAIT_FIRST_INPUT
    WAIT_FIRST_INPUT,                      // Initial waiting input, values latched into temp reg, next state depends on MSB of input (number or op) + specific op (ac, neg) (eq don't do anything here)
    FIRST_INPUT_NUMBER,                    // PRESSED Number: Shift reg A and load number input (can be signed), DISPLAY_AFTER_FIRST_INPUT next
    DISPLAY_AFTER_FIRST_INPUT,             // Display updated reg A value and return to WAIT_FIRST_INPUT
    FIRST_INPUT_OP,                        // PRESSED Op: (both from WAIT_FIRST_INPUT and WAIT_SECOND_INPUT_BEFORE_VALUE): Load operation, display current operation state (and for any subsequent FSM state), WAIT_SECOND_INPUT_BEFORE_VALUE next
    FIRST_INPUT_NEG,                       // PRESSED (-): negate reg A value and toggle reg_a_input_neg flag (this flag should be reset for AC, EQ), WAIT_FIRST_INPUT next
    WAIT_SECOND_INPUT_BEFORE_VALUE,        // Wait for second input, next state depends on MSB of input (number or op) + specific op (ac, eq, neg)
    SECOND_INPUT_NEG_BEFORE_VALUE,         // PRESSED (-): negate reg B value and toggle reg_b_input_neg flag (this flag should be reset for AC, EQ, Second OP), WAIT_SECOND_INPUT_BEFORE_VALUE next (this action alone does not constitute a value input)
    COPY_A_TO_B,                           // PRESSED Eq: copy reg A to reg B, perform A = A op A, EQUAL_AFTER_SECOND_VALUE next
    SECOND_INPUT_NUMBER,                   // PRESSED Number: Shift reg B and load number input (can be signed), DISPLAY_AFTER_SECOND_INPUT next
    DISPLAY_AFTER_SECOND_INPUT,            // Display updated reg B value and return to WAIT_SECOND_INPUT_BEFORE_VALUE
    WAIT_SECOND_INPUT_AFTER_VALUE,         // Wait for second input after some value has been entered, next state depends on MSB of input (number or op) + specific op (ac, eq, neg)
    SECOND_INPUT_NEG_AFTER_VALUE,          // PRESSED (-): negate reg B value and toggle reg_b_input_neg flag (this flag should be reset for AC, EQ, Second OP), WAIT_SECOND_INPUT_AFTER_VALUE next
    SECOND_INPUT_OP_CALCULATE,             // PRESSED Op: A = A op B, and load in new operation while ALU gets old operation, SECOND_INPUT_OP_CALCULATE_WAIT_RESULT next
    SECOND_INPUT_OP_CALCULATE_WAIT_RESULT, // Wait for ALU result to be valid after SECOND_INPUT_OP_CALCULATE, DISPLAY_AFTER_SECOND_OP next
    DISPLAY_AFTER_SECOND_OP,               // Display updated reg A value and return to WAIT_SECOND_INPUT_BEFORE_VALUE
    EQUAL_AFTER_SECOND_VALUE,              // PRESSED Eq: A = A op B, EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT next
    EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT,  // Wait for ALU result to be valid after EQUAL_AFTER_SECOND_VALUE, DISPLAY_AFTER_EQUAL next
    DISPLAY_AFTER_EQUAL,                   // Display updated reg A value and return to WAIT_FIRST_INPUT
    WAIT_INPUT_AFTER_EQUAL,                // Wait for input after equal, next state depends on MSB of input (number or op) + specific op (ac, neg)
    INPUT_NEG_AFTER_EQUAL,                 // PRESSED (-): negate reg A value (no need for flag since no input can occur without erasing reg A), DISPLAY_AFTER_EQUAL next
    CLEAR_AFTER_EQUAL,                     // PRESSED Number: after EQUAL, clear and load new number into temp reg (clear all neg flags), FIRST_INPUT_NUMBER next
    ERROR                                  // If the ALU result ever reads an error from SECOND_INPUT_OP_CALCULATE or EQUAL_AFTER_SECOND_VALUE, go to this state and wait for AC button press
  } fsm_state_t;

  fsm_state_t current_state;

  // Registers
  logic [DATA_WIDTH-1:0] reg_a, reg_b;    // Main registers A and B to hold input values and ALU results
  logic [3:0]            temp_input;      // Temporary 4-bit register to hold number input before shifting into reg A or B or op
  logic [1:0]            current_op;      // Current operation to perform (00: ADD, 01: SUB, 10: MUL, 11: DIV)
  logic reg_a_input_neg, reg_b_input_neg; // Flags to indicate if reg A or reg B input is negative (so REG = REG << 4 - input).

  // Control Signals - FSM
  logic load_op;         // Load operation from temp register to current_op
  logic reg_a_load;      // Load value from temp to reg A (with shift left by 4)
  logic reg_b_load;      // Load value from temp to reg B (with shift left by 4)
  logic reg_a_invert;    // Invert reg A value (2's comp)
  logic reg_b_invert;    // Invert reg B value (2's comp)
  logic clear_regs;      // Clear reg A and reg B to 0, along with neg flags (preserve temp_input)
  logic show_current_op; // Show current op state via o_*_state_display outputs
  logic output_a_not_b;  // Output reg A if 1, reg B if 0
  
  // Control Signals - Data Handshake
  logic load_temp;       // Indicate if current loading inputs into temp reg
  assign load_temp = i_button_valid && o_button_ready;
  logic reading_result;  // Indicates if currently reading ALU result into reg A
  assign reading_result = i_alu_result_valid && o_alu_result_ready;
  
  // Output Signals
  logic button_input_ready; // Handshake signal for button input
  assign o_button_ready = button_input_ready;
  logic alu_input_valid; // Handshake signal for ALU input
  logic alu_out_ready;   // Handshake signals for ALU output
  assign o_alu_input_a = reg_a;
  assign o_alu_input_b = reg_b;
  assign o_alu_input_op = current_op;
  assign o_alu_input_signed = i_2s_comp_mode;
  assign o_alu_input_valid = alu_input_valid;
  assign o_alu_result_ready = alu_out_ready;
  assign o_add_state_display = (current_op == 2'b00) && show_current_op;
  assign o_sub_state_display = (current_op == 2'b01) && show_current_op;
  assign o_mul_state_display = (current_op == 2'b10) && show_current_op;
  assign o_div_state_display = (current_op == 2'b11) && show_current_op;
  logic [DATA_WIDTH-1:0] output_value; // Value to output to display driver
  logic display_valid;   // Handshake signal for display output
  assign o_display_data    = output_value;
  assign o_display_valid   = display_valid;
  assign o_display_2s_comp = i_2s_comp_mode;

  // Full adder instance (for inverting and handling shift + load operations)
  logic [DATA_WIDTH-1:0] fa_a, fa_b, fa_sum;
  logic                  fa_carry_in;
  full_adder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) fa_inst (
    .a        (fa_a),
    .b        (fa_b),
    .carry_in (fa_carry_in),
    .sum      (fa_sum),
    .carry_out() // Unused
  );

  // State transition
  always_ff @(posedge clk or negedge rst_n) begin : fsm_state_register
    if (!rst_n) begin
      current_state <= AC;
    end else begin
      case (current_state)
        AC: 
          begin
            //TODO
          end
        DISPLAY_AFTER_AC:
          begin
            //TODO...
          end
      endcase
    end
  end

  // Control signal combinational logic
  always_comb begin : fsm_control_signals_comb
    case (current_state)
      AC: 
        begin
          //TODO
        end
      DISPLAY_AFTER_AC:
        begin
          //TODO...
        end
    endcase
  end

  // Data path blocks
  always_ff @(posedge clk or negedge rst_n) begin : a_register_block
    if (!rst_n) begin
      
    end else begin
      
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : b_register_block
    if (!rst_n) begin
      
    end else begin
      
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : temp_input_register_block
    if (!rst_n) begin
      
    end else begin
      //TODO: don't load if we are writing to ALU, only load when alu ready && valid
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : current_op_register_block
    if (!rst_n) begin
      
    end else begin
      
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : reg_a_input_neg_register_block
    if (!rst_n) begin
      
    end else begin
      
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : reg_b_input_neg_register_block
    if (!rst_n) begin
      
    end else begin
      
    end
  end

  // Adder inputs combinational logic
  always_comb begin : fa_inputs_comb

  end
endmodule