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
    output logic                  o_display_value_is_neg,
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
    DISPLAY_AFTER_EQUAL,                   // Display updated reg A value and return to WAIT_INPUT_AFTER_EQUAL
    WAIT_INPUT_AFTER_EQUAL,                // Wait for input after equal, next state depends on MSB of input (number or op) + specific op (ac, neg)
    INPUT_NEG_AFTER_EQUAL,                 // PRESSED (-): negate reg A value (no need for flag since no input can occur without erasing reg A), DISPLAY_AFTER_EQUAL next
    CLEAR_AFTER_EQUAL,                     // PRESSED Number: after EQUAL, clear and load new number into temp reg (clear all neg flags), FIRST_INPUT_NUMBER next
    DISPLAY_ERROR,                         // If the ALU result ever reads an error from SECOND_INPUT_OP_CALCULATE or EQUAL_AFTER_SECOND_VALUE, go to this state and display Error
    ERROR_WAIT                             // In error, wait for AC
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
  logic clear_reg_b;     // Clear reg B only (clear_regs takes priority) (when in wait_second_input_before_values)
  logic show_current_op; // Show current op state via o_*_state_display outputs
  logic output_a_not_b;  // Output reg A if 1, reg B if 0
  logic reset_neg_flags; // Reset both A and B neg flags to 0
  
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
  assign output_value = output_a_not_b ? reg_a : reg_b;
  assign o_display_data    = o_display_value_is_neg ? fa_sum : output_value; // If value is negative, flip sign using full adder (2's comp)
  assign o_display_valid   = display_valid;
  assign o_display_value_is_neg = i_2s_comp_mode ? (output_value[DATA_WIDTH-1] == 1'b1) : '0; // In 2's comp mode, display value is negative if MSB is 1, else always 0

  // Full adder instance (for inverting and handling shift + load operations)
  logic [DATA_WIDTH-1:0] fa_a, fa_b, fa_sum;
  logic                  fa_carry_in;
  logic                  fa_carry_out; // TODO: this is used to handle overflow protections for unsigned values
  full_adder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) fa_inst (
    .a        (fa_a),
    .b        (fa_b),
    .carry_in (fa_carry_in),
    .sum      (fa_sum),
    .carry_out(fa_carry_out)
  );

  // State transition
  always_ff @(posedge clk or negedge rst_n) begin : fsm_state_register
    if (!rst_n) begin
      current_state <= AC;
    end else begin
      case (current_state)
        AC:
          begin
            // Pressed AC from any WAIT_INPUT state: clear all registers and flags, go to DISPLAY_AFTER_AC
            current_state <= DISPLAY_AFTER_AC;
          end
        DISPLAY_AFTER_AC:
          begin
            // Display cleared reg A value (0), and return to WAIT_FIRST_INPUT
            if (o_display_valid && i_display_ready) begin
              current_state <= WAIT_FIRST_INPUT;
            end
          end
        WAIT_FIRST_INPUT:
          begin
            // Initial waiting input, values latched into temp reg, next state depends on MSB of input (number or op) + specific op (ac, neg) (eq don't do anything here)
            if (load_temp) begin
              if (i_button_data[4] == 1'b0) begin
                // Input is NUMBER
                current_state <= FIRST_INPUT_NUMBER;
              end else if (i_button_data[2] == 1'b0) begin
                // Input is OP
                current_state <= FIRST_INPUT_OP;
              end else begin
                if (i_button_data[1:0] == 2'b01) begin
                  // AC
                  current_state <= AC;
                end else if (i_button_data[1:0] == 2'b10) begin
                  // Neg
                  current_state <= FIRST_INPUT_NEG;
                end
              end
            end
          end
        FIRST_INPUT_NUMBER:
          begin
            // PRESSED Number: Shift reg A and load number input (can be signed), DISPLAY_AFTER_FIRST_INPUT next
            current_state <= DISPLAY_AFTER_FIRST_INPUT;
          end
        DISPLAY_AFTER_FIRST_INPUT:
          begin
            // Display updated reg A value and return to WAIT_FIRST_INPUT
            if (o_display_valid && i_display_ready) begin
              current_state <= WAIT_FIRST_INPUT;
            end
          end
        FIRST_INPUT_OP:
          begin
            // PRESSED Op: (both from WAIT_FIRST_INPUT and WAIT_SECOND_INPUT_BEFORE_VALUE): Load operation, display current operation state (and for any subsequent FSM state), WAIT_SECOND_INPUT_BEFORE_VALUE next
            current_state <= WAIT_SECOND_INPUT_BEFORE_VALUE;
          end
        FIRST_INPUT_NEG:
          begin
            // PRESSED (-): negate reg A value and toggle reg_a_input_neg flag (this flag should be reset for AC, EQ), WAIT_FIRST_INPUT next
            current_state <= WAIT_FIRST_INPUT;
          end
        WAIT_SECOND_INPUT_BEFORE_VALUE:
          begin
            // Wait for second input, next state depends on MSB of input (number or op) + specific op (ac, eq, neg)
            if (load_temp) begin
              if (i_button_data[4] == 1'b0) begin
                // Input is NUMBER
                current_state <= SECOND_INPUT_NUMBER;
              end else if (i_button_data[2] == 1'b0) begin
                // Input is OP
                current_state <= FIRST_INPUT_OP;
              end else begin
                if (i_button_data[1:0] == 2'b01) begin
                  // AC
                  current_state <= AC;
                end else if (i_button_data[1:0] == 2'b10) begin
                  // Neg
                  current_state <= SECOND_INPUT_NEG_BEFORE_VALUE;
                end else if (i_button_data[1:0] == 2'b00) begin
                  // Eq
                  current_state <= COPY_A_TO_B;
                end
              end
            end
          end
        SECOND_INPUT_NEG_BEFORE_VALUE:
          begin
            // PRESSED (-): negate reg B value and toggle reg_b_input_neg flag (this flag should be reset for AC, EQ, Second OP), WAIT_SECOND_INPUT_BEFORE_VALUE next (this action alone does not constitute a value input)
            current_state <= WAIT_SECOND_INPUT_BEFORE_VALUE;
          end
        COPY_A_TO_B:
          begin
            // PRESSED Eq: copy reg A to reg B, perform A = A op A, EQUAL_AFTER_SECOND_VALUE next
            current_state <= EQUAL_AFTER_SECOND_VALUE;
          end
        SECOND_INPUT_NUMBER:
          begin
            // PRESSED Number: Shift reg B and load number input (can be signed), DISPLAY_AFTER_SECOND_INPUT next
            current_state <= DISPLAY_AFTER_SECOND_INPUT;
          end
        DISPLAY_AFTER_SECOND_INPUT:
          begin
            // Display updated reg B value and return to WAIT_SECOND_INPUT_BEFORE_VALUE
            if (o_display_valid && i_display_ready) begin
              current_state <= WAIT_SECOND_INPUT_BEFORE_VALUE;
            end
          end
        WAIT_SECOND_INPUT_AFTER_VALUE:
          begin
            // Wait for second input after some value has been entered, next state depends on MSB of input (number or op) + specific op (ac, eq, neg)
            if (load_temp) begin
              if (i_button_data[4] == 1'b0) begin
                // Input is NUMBER
                current_state <= SECOND_INPUT_NUMBER;
              end else if (i_button_data[2] == 1'b0) begin
                // Input is OP
                current_state <= SECOND_INPUT_OP_CALCULATE;
              end else begin
                if (i_button_data[1:0] == 2'b01) begin
                  // AC
                  current_state <= AC;
                end else if (i_button_data[1:0] == 2'b10) begin
                  // Neg
                  current_state <= SECOND_INPUT_NEG_AFTER_VALUE;
                end else if (i_button_data[1:0] == 2'b00) begin
                  // Eq
                  current_state <= EQUAL_AFTER_SECOND_VALUE;
                end
              end
            end
          end
        SECOND_INPUT_NEG_AFTER_VALUE:
          begin
            // PRESSED (-): negate reg B value and toggle reg_b_input_neg flag (this flag should be reset for AC, EQ, Second OP), WAIT_SECOND_INPUT_AFTER_VALUE next
            current_state <= WAIT_SECOND_INPUT_AFTER_VALUE;
          end
        SECOND_INPUT_OP_CALCULATE:
          begin
            // PRESSED Op: A = A op B, and load in new operation while ALU gets old operation, SECOND_INPUT_OP_CALCULATE_WAIT_RESULT next
            if (o_alu_input_valid && i_alu_input_ready) begin
              current_state <= SECOND_INPUT_OP_CALCULATE_WAIT_RESULT;
            end
          end
        SECOND_INPUT_OP_CALCULATE_WAIT_RESULT:
          begin
            // Wait for ALU result to be valid after SECOND_INPUT_OP_CALCULATE, DISPLAY_AFTER_SECOND_OP next
            if (reading_result) begin
              if (i_alu_error) current_state <= DISPLAY_ERROR;
              else             current_state <= DISPLAY_AFTER_SECOND_OP;
            end
          end
        DISPLAY_AFTER_SECOND_OP:
          begin
            // Display updated reg A value and return to WAIT_SECOND_INPUT_BEFORE_VALUE
            if (o_display_valid && i_display_ready) begin
              current_state <= WAIT_SECOND_INPUT_BEFORE_VALUE;
            end
          end
        EQUAL_AFTER_SECOND_VALUE:
          begin
            // PRESSED Eq: A = A op B, EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT next
            if (o_alu_input_valid && i_alu_input_ready) begin
              current_state <= EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT;
            end
          end
        EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT:
          begin
            // Wait for ALU result to be valid after EQUAL_AFTER_SECOND_VALUE, DISPLAY_AFTER_EQUAL next
            if (reading_result) begin
              if (i_alu_error) current_state <= DISPLAY_ERROR;
              else             current_state <= DISPLAY_AFTER_EQUAL;
            end
          end
        DISPLAY_AFTER_EQUAL:
          begin
            // Display updated reg A value and move to WAIT_INPUT_AFTER_EQUAL
            if (o_display_valid && i_display_ready) begin
              current_state <= WAIT_INPUT_AFTER_EQUAL;
            end
          end
        WAIT_INPUT_AFTER_EQUAL:
          begin
            // Wait for input after equal, next state depends on MSB of input (number or op) + specific op (ac, neg)
            if (load_temp) begin
              if (i_button_data[4] == 1'b0) begin
                // Input is NUMBER
                current_state <= CLEAR_AFTER_EQUAL;
              end else if (i_button_data[2] == 1'b0) begin
                // Input is OP
                current_state <= WAIT_SECOND_INPUT_BEFORE_VALUE;
              end else begin
                if (i_button_data[1:0] == 2'b01) begin
                  // AC
                  current_state <= AC;
                end else if (i_button_data[1:0] == 2'b10) begin
                  // Neg
                  current_state <= INPUT_NEG_AFTER_EQUAL;
                end else if (i_button_data[1:0] == 2'b00) begin
                  // Eq
                  current_state <= EQUAL_AFTER_SECOND_VALUE;
                end
              end
            end
          end
        INPUT_NEG_AFTER_EQUAL:
          begin
            // PRESSED (-): negate reg A value (no need for flag since no input can occur without erasing reg A), DISPLAY_AFTER_EQUAL next
            current_state <= DISPLAY_AFTER_EQUAL;
          end
        CLEAR_AFTER_EQUAL:
          begin
            // PRESSED Number: after EQUAL, clear and load new number into temp reg (clear all neg flags), FIRST_INPUT_NUMBER next
            current_state <= FIRST_INPUT_NUMBER;
          end
        DISPLAY_ERROR:
          begin
            // If the ALU result ever reads an error from SECOND_INPUT_OP_CALCULATE or EQUAL_AFTER_SECOND_VALUE, go to this state and wait for AC button press
            if (o_display_valid && i_display_ready) begin
              current_state <= ERROR_WAIT;
            end
          end
        ERROR_WAIT:
          begin
            // Wait in error state until AC is pressed
            if (load_temp) begin
              if (i_button_data[2:0] == 3'b001) begin
                // AC
                current_state <= AC;
              end
            end
          end
        default:
          begin
            // This should not occur
            current_state <= AC;
          end
      endcase
    end
  end

  // Control signal combinational logic
  always_comb begin : fsm_control_signals_comb
    case (current_state)
      AC:
        begin
          // Pressed AC from any WAIT_INPUT state: clear all registers and flags, go to DISPLAY_AFTER_AC
          clear_regs         = 1;
          reset_neg_flags    = 1;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      DISPLAY_AFTER_AC:
        begin
          // Display cleared reg A value (0), and return to WAIT_FIRST_INPUT
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      WAIT_FIRST_INPUT:
        begin
          // Initial waiting input, values latched into temp reg, next state depends on MSB of input (number or op) + specific op (ac, neg) (eq don't do anything here)
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      FIRST_INPUT_NUMBER:
        begin
          // PRESSED Number: Shift reg A and load number input (can be signed), DISPLAY_AFTER_FIRST_INPUT next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      DISPLAY_AFTER_FIRST_INPUT:
        begin
          // Display updated reg A value and return to WAIT_FIRST_INPUT
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      FIRST_INPUT_OP:
        begin
          // PRESSED Op: (both from WAIT_FIRST_INPUT and WAIT_SECOND_INPUT_BEFORE_VALUE): Load operation, display current operation state (and for any subsequent FSM state), WAIT_SECOND_INPUT_BEFORE_VALUE next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      FIRST_INPUT_NEG:
        begin
          // PRESSED (-): negate reg A value and toggle reg_a_input_neg flag (this flag should be reset for AC, EQ), WAIT_FIRST_INPUT next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      WAIT_SECOND_INPUT_BEFORE_VALUE:
        begin
          // Wait for second input, next state depends on MSB of input (number or op) + specific op (ac, eq, neg)
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      SECOND_INPUT_NEG_BEFORE_VALUE:
        begin
          // PRESSED (-): negate reg B value and toggle reg_b_input_neg flag (this flag should be reset for AC, EQ, Second OP), WAIT_SECOND_INPUT_BEFORE_VALUE next (this action alone does not constitute a value input)
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      COPY_A_TO_B:
        begin
          // PRESSED Eq: copy reg A to reg B, perform A = A op A, EQUAL_AFTER_SECOND_VALUE next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      SECOND_INPUT_NUMBER:
        begin
          // PRESSED Number: Shift reg B and load number input (can be signed), DISPLAY_AFTER_SECOND_INPUT next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      DISPLAY_AFTER_SECOND_INPUT:
        begin
          // Display updated reg B value and return to WAIT_SECOND_INPUT_BEFORE_VALUE
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      WAIT_SECOND_INPUT_AFTER_VALUE:
        begin
          // Wait for second input after some value has been entered, next state depends on MSB of input (number or op) + specific op (ac, eq, neg)
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      SECOND_INPUT_NEG_AFTER_VALUE:
        begin
          // PRESSED (-): negate reg B value and toggle reg_b_input_neg flag (this flag should be reset for AC, EQ, Second OP), WAIT_SECOND_INPUT_AFTER_VALUE next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      SECOND_INPUT_OP_CALCULATE:
        begin
          // PRESSED Op: A = A op B, and load in new operation while ALU gets old operation, SECOND_INPUT_OP_CALCULATE_WAIT_RESULT next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      SECOND_INPUT_OP_CALCULATE_WAIT_RESULT:
        begin
          // Wait for ALU result to be valid after SECOND_INPUT_OP_CALCULATE, DISPLAY_AFTER_SECOND_OP next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      DISPLAY_AFTER_SECOND_OP:
        begin
          // Display updated reg A value and return to WAIT_SECOND_INPUT_BEFORE_VALUE
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      EQUAL_AFTER_SECOND_VALUE:
        begin
          // PRESSED Eq: A = A op B, EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT:
        begin
          // Wait for ALU result to be valid after EQUAL_AFTER_SECOND_VALUE, DISPLAY_AFTER_EQUAL next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      DISPLAY_AFTER_EQUAL:
        begin
          // Display updated reg A value and move to WAIT_INPUT_AFTER_EQUAL
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      WAIT_INPUT_AFTER_EQUAL:
        begin
          // Wait for input after equal, next state depends on MSB of input (number or op) + specific op (ac, neg)
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      INPUT_NEG_AFTER_EQUAL:
        begin
          // PRESSED (-): negate reg A value (no need for flag since no input can occur without erasing reg A), DISPLAY_AFTER_EQUAL next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      CLEAR_AFTER_EQUAL:
        begin
          // PRESSED Number: after EQUAL, clear and load new number into temp reg (clear all neg flags), FIRST_INPUT_NUMBER next
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      DISPLAY_ERROR:
        begin
          // If the ALU result ever reads an error from SECOND_INPUT_OP_CALCULATE or EQUAL_AFTER_SECOND_VALUE, go to this state and wait for AC button press
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      ERROR_WAIT:
        begin
          // Wait in error state until AC is pressed
          clear_regs         = 0;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;
        end
      default:
        begin
          // This should not occur
          clear_regs         = 1;
          reset_neg_flags    = 0;
          clear_reg_b        = 0;

          load_op            = 0;
          reg_a_load         = 0;
          reg_b_load         = 0;
          
          reg_a_invert       = 0;
          reg_b_invert       = 0;
          
          show_current_op    = 0;
          output_a_not_b     = 0;

          button_input_ready = 0;
          alu_input_valid    = 0;
          alu_out_ready      = 0;
          display_valid      = 0;

        end
    endcase
  end

  // Data path blocks
  always_ff @(posedge clk or negedge rst_n) begin : a_register_block
    if (!rst_n) begin
      reg_a <= '0;
    end else begin
      if (clear_regs) begin
        reg_a <= '0;
      end else if (reg_a_load || reg_a_invert) begin
        reg_a <= fa_sum; // Load in shifted and added result / inverted result
      end else if (reading_result) begin
        reg_a <= i_alu_result; 
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : b_register_block
    if (!rst_n) begin
      reg_b <= '0;
    end else begin
      if (clear_regs || clear_reg_b) begin
        reg_b <= '0;
      end else if (reg_b_load || reg_b_invert) begin
        reg_b <= fa_sum; // Load in shifted and added result / inverted result
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : temp_input_register_block
    if (!rst_n) begin
      temp_input <= '0;
    end else begin
      if (load_temp) begin
        temp_input <= i_button_data[3:0];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : current_op_register_block
    if (!rst_n) begin
      current_op <= 2'b00;
    end else begin
      if (load_op) begin
        // Only load the op once current one is read by ALU (if we are writing to ALU)
        if (o_alu_input_valid) begin
            if (i_alu_input_ready) current_op <= temp_input[1:0];
        end else begin
            current_op <= temp_input[1:0];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : reg_a_input_neg_register_block
    if (!rst_n) begin
      reg_a_input_neg <= '0;
    end else begin
      if (clear_regs || reset_neg_flags || ~i_2s_comp_mode) begin
        // Clear, reset, or not doing negative values
        reg_a_input_neg <= '0;
      end else if (reg_a_invert) begin
        // Toggle the neg flag
        reg_a_input_neg <= ~reg_a_input_neg;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : reg_b_input_neg_register_block
    if (!rst_n) begin
      reg_b_input_neg <= '0;
    end else begin
      if (clear_regs || reset_neg_flags || ~i_2s_comp_mode) begin
        // Clear, reset, or not doing negative values
        reg_b_input_neg <= '0;
      end else if (reg_b_invert) begin
        // Toggle the neg flag
        reg_b_input_neg <= ~reg_b_input_neg;
      end
    end
  end

  // Adder inputs combinational logic
  always_comb begin : fa_inputs_comb
    // Default assignments
    fa_a        = '0;
    fa_b        = '0;
    fa_carry_in = 1'b0;

    // Determine adder inputs based on control signals
    if (reg_a_load) begin
      // Shift left reg A by 4 and +/- temp_input
      fa_a = { reg_a[DATA_WIDTH-1:4], 4'b0 }; // TODO: if decimal input, handle by adding another smaller width adder to add (a << 3 + a << 1)
      fa_b = { {(DATA_WIDTH-4){1'b0}}, temp_input};
      fa_b = reg_a_input_neg ? ~fa_b : fa_b;
      fa_carry_in = reg_a_input_neg;
    end else if (reg_b_load) begin
      // Shift left reg B by 4 and +/- temp_input
      fa_a = { reg_b[DATA_WIDTH-1:4], 4'b0 }; // TODO: if decimal input, handle by adding another smaller width adder to add (a << 3 + a << 1)
      fa_b = { {(DATA_WIDTH-4){1'b0}}, temp_input};
      fa_b = reg_b_input_neg ? ~fa_b : fa_b;
      fa_carry_in = reg_b_input_neg;
    end else if (reg_a_invert) begin
      // Invert reg A (2's comp)
      fa_a = ~reg_a;
      fa_b = '0;
      fa_carry_in = 1'b1;
    end else if (reg_b_invert) begin
      // Invert reg B (2's comp)
      fa_a = ~reg_b;
      fa_b = '0;
      fa_carry_in = 1'b1;
    end else if (display_valid) begin
      // Outputting data, convert to abs value only if o_display_value_is_neg is set
      if (o_display_value_is_neg) begin
        fa_a = ~output_value;
        fa_b = '0;
        fa_carry_in = 1'b1;
      end
    end
  end
endmodule