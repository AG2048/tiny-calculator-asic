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
  /*
    ALU module that performs + - * / operations.

    Input follows a valid-ready handshake protocol.
    At input (i_ready && i_valid), loads:
        i_alu_input_a: first operand
        i_alu_input_b: second operand
        i_alu_input_op: operation
        i_alu_input_signed: signed/unsigned for DIV only (MUL outputs same width as inputs, so signed/unsigned doesn't matter) TODO: may consider adding MUL bits later
          Sign of inputs are also recorded at input time
    Div by zero error is detected at input time, will immediately output a random number with o_alu_error high at output time.

    ADD/SUB: 1 cycle operation using a full adder
    MUL:     DATA_WIDTH cycle operation by shift-and-add algorithm (TODO: currently 1 cycle for placeholder)
    DIV:     DATA_WIDTH cycle operation by TODO algorithm (TODO: currently 1 cycle for placeholder)
             Division result may be sign flipped at the end based on input signs.

    All operation can use the same full adder. 

    Output follows a valid-ready handshake protocol.
    When outputting result, o_alu_result_valid is high, and o_alu_error is high if error occurred (e.g., div by zero).

    input ready is only high when ALU is ready to accept new inputs (i.e., not busy processing previous inputs).
    output valid is only high when result is ready to be read. 
  */
  // TODO: this is mostly a placeholder implementation, replace with actual multi-cycle implementations for MUL and DIV later

  typedef enum logic [2:0] {
    WAIT_INPUT,
    ADD_OP,
    SUB_OP,
    MUL_OP,
    DIV_OP, // TODO: may need more states to track sign flipping for signed division
    OUTPUT_RESULT,
    OUTPUT_ERROR
  } alu_state_t;

  alu_state_t current_state;

  // Registers
  logic [DATA_WIDTH-1:0] result_reg;
  logic [DATA_WIDTH-1:0] a_reg, b_reg;
  logic                  a_is_neg, b_is_neg; // For signed operations, track the values at input time
  assign o_alu_result = result_reg;

  // Output signals
  logic input_ready, result_valid, error_flag;
  assign o_alu_input_ready = input_ready;
  assign o_alu_result_valid = result_valid;
  assign o_alu_error = error_flag;

  // Control signals
  logic load_a, load_b;
  logic a_input_sel, b_input_sel; // Input selection for loading A and B (TODO: may need multiple possible inputs to A/B)
  logic load_result;
  logic result_input_sel; // Result input selection (e.g., from ALU operation output, or error code) TODO

  // State transition
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= WAIT_INPUT;
    end else begin
      case (current_state)
        WAIT_INPUT:
          begin
            if (i_alu_input_valid && o_alu_input_ready) begin
              case (i_alu_input_op)
                2'b00: current_state <= ADD_OP;
                2'b01: current_state <= SUB_OP;
                2'b10: current_state <= MUL_OP;
                2'b11: 
                  begin 
                    if (i_alu_input_b == 0) begin
                      current_state <= OUTPUT_ERROR; // Division by zero error TODO check if this is best way to do this
                    end else begin
                      current_state <= DIV_OP;
                    end
                  end
                default: current_state <= WAIT_INPUT;
              endcase
            end
          end
        ADD_OP:
          begin
            current_state <= OUTPUT_RESULT;
          end
        SUB_OP:
          begin
            current_state <= OUTPUT_RESULT;
          end
        MUL_OP:
          begin
            current_state <= OUTPUT_RESULT; // TODO: Temp doing 1 cycle MUL, replace with multi-cycle MUL FSM later
          end
        DIV_OP:
          begin
            current_state <= OUTPUT_RESULT; // TODO: Temp doing 1 cycle DIV, replace with multi-cycle DIV FSM later
          end
        OUTPUT_RESULT:
          begin
            if (o_alu_result_valid && i_alu_result_ready) begin
              current_state <= WAIT_INPUT;
            end
          end
        OUTPUT_ERROR:
          begin
            if (o_alu_result_valid && i_alu_result_ready) begin
              current_state <= WAIT_INPUT;
            end
          end
        default:
          begin
            current_state <= WAIT_INPUT;
          end
      endcase
    end
  end

  // Control signals generation
  always_comb begin
    case (current_state)
      WAIT_INPUT: 
        begin
          input_ready = 1;
          result_valid = 0;
          error_flag = 0;

          load_a = 1;
          a_input_sel = 1; // Direct input
          load_b = 1;
          b_input_sel = 1; // Direct input
          load_result = 0;
          result_input_sel = 0;
        end
      ADD_OP:
        begin
          input_ready = 0;
          result_valid = 0;
          error_flag = 0;

          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 1;
          result_input_sel = 1; // From ALU operation
        end
      SUB_OP:
        begin
          input_ready = 0;
          result_valid = 0;
          error_flag = 0;

          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 1;
          result_input_sel = 1; // From ALU operation
        end
      MUL_OP:
        begin
          input_ready = 0;
          result_valid = 0;
          error_flag = 0;

          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 1;
          result_input_sel = 1; // From ALU operation
        end
      DIV_OP:
        begin
          input_ready = 0;
          result_valid = 0;
          error_flag = 0;

          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 1;
          result_input_sel = 1; // From ALU operation
        end
      OUTPUT_RESULT:
        begin
          input_ready = 0;
          result_valid = 1;
          error_flag = 0;
          
          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 0;
          result_input_sel = 0;
        end
      OUTPUT_ERROR:
        begin
          input_ready = 0;
          result_valid = 1;
          error_flag = 1;

          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 0;
          result_input_sel = 0;
        end
      default:
        begin
          input_ready = 0;
          result_valid = 0;
          error_flag = 0;

          load_a = 0;
          a_input_sel = 0;
          load_b = 0;
          b_input_sel = 0;
          load_result = 0;
          result_input_sel = 0;
        end
    endcase
  end
  
  // Data path operations
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_reg <= '0;
      b_reg <= '0;
      a_is_neg <= 1'b0;
      b_is_neg <= 1'b0;
      result_reg <= '0;
    end else begin
      if (load_a) begin // TODO: this is a sample way to get value, change later. 
        if (a_input_sel) begin
          a_reg <= i_alu_input_a;
          a_is_neg <= i_alu_input_signed && i_alu_input_a[DATA_WIDTH-1];
        end else begin
          a_reg <= ~i_alu_input_a + 1; // 2's complement
        end
      end

      if (load_b) begin
        if (b_input_sel) begin
          b_reg <= i_alu_input_b;
          b_is_neg <= i_alu_input_signed && i_alu_input_b[DATA_WIDTH-1];
        end else begin
          b_reg <= ~i_alu_input_b + 1; // 2's complement
        end
      end

      if (load_result) begin
        if (result_input_sel) begin // TODO: currently only ALU operation output
          case (current_state)
            ADD_OP:
              result_reg <= a_reg + b_reg;
            SUB_OP:
              result_reg <= a_reg - b_reg;
            MUL_OP:
              result_reg <= a_reg * b_reg;
            DIV_OP:
              result_reg <= a_reg / b_reg; // TODO: handle division by zero case
            default:
              result_reg <= '0;
          endcase
        end else begin
          result_reg <= '0; // Placeholder for error code or other inputs
        end
      end
    end
  end

endmodule