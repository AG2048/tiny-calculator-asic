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
  localparam COUNTER_WIDTH = $clog2(DATA_WIDTH); // Width to count from 0 to DATA_WIDTH-1

  // FSM states
  typedef enum logic [3:0] {
    WAIT_INPUT,
    ADD_OP,
    SUB_OP,
    MUL_INIT,
    MUL_OP,
    DIV_FLIP_A,
    DIV_FLIP_B,
    DIV_INIT,
    DIV_OP,
    DIV_POST,
    OUTPUT_RESULT,
    OUTPUT_ERROR
  } alu_state_t;

  alu_state_t current_state;

  // Registers
  logic [DATA_WIDTH-1:0] result_reg;
  logic [2*DATA_WIDTH-2:0] a_reg;
  logic [DATA_WIDTH-1:0] b_reg;
  assign o_alu_result = result_reg;

  // Output signals
  logic input_ready, result_valid, error_flag;
  assign o_alu_input_ready = input_ready;
  assign o_alu_result_valid = result_valid;
  assign o_alu_error = error_flag;

  // Control signals
  logic in_add, in_sub, in_mul, in_div; // Signals to specify which operation is being performed
  logic reset_counter;
  logic [COUNTER_WIDTH-1:0] counter; // Counter for multi-cycle operations
  logic flipping_a, flipping_b; // Signals to indicate if operands need to be sign-flipped
  logic div_result_neg_reg; // Register to hold if div result is negative, to be set along with state transition
  logic in_post_div; // Signal to indicate we are in post-division phase, flip result if needed

  // ALU full adder instance
  logic [DATA_WIDTH-1:0] adder_output, adder_a_input, adder_b_input;
  logic adder_subtract;
  full_adder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) alu_adder (
    .a       (adder_a_input),
    .b       (adder_b_input),
    .carry_in(adder_subtract), // For subtraction, add 1 at LSB (2's complement)
    .sum     (adder_output)
  );

  // Logic signals
  logic divides;
  assign divides = ~adder_output[DATA_WIDTH-1]; // If A - B >= 0, then A divides B

  // State transition
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= WAIT_INPUT;
      div_result_neg_reg <= 1'b0;
    end else begin
      case (current_state)
        WAIT_INPUT:
          begin
            if (i_alu_input_valid && o_alu_input_ready) begin
              // Load inputs
              // Determine next state based on operation
              case (i_alu_input_op)
                2'b00: current_state <= ADD_OP;
                2'b01: current_state <= SUB_OP;
                2'b10: current_state <= MUL_INIT;
                2'b11: 
                  begin
                    // Div
                    if (i_alu_input_b == 0) current_state <= OUTPUT_ERROR; // Div by zero error
                    else begin
                      // Determine if need to flip signs
                      div_result_neg_reg <= i_alu_input_signed && 
                                            (i_alu_input_a[DATA_WIDTH-1] ^ i_alu_input_b[DATA_WIDTH-1]);
                      if (i_alu_input_signed) begin
                        current_state <= DIV_FLIP_A;
                      end else begin
                        current_state <= DIV_INIT;
                      end
                    end
                  end
                default: current_state <= WAIT_INPUT; // Should not happen
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
        MUL_INIT:
          begin
            current_state <= MUL_OP;
          end
        MUL_OP:
          begin
            if (counter == 0) begin
              current_state <= OUTPUT_RESULT;
            end
          end
        DIV_FLIP_A:
          begin
            current_state <= DIV_FLIP_B;
          end
        DIV_FLIP_B:
          begin
            current_state <= DIV_INIT;
          end
        DIV_INIT:
          begin
            current_state <= DIV_OP;
          end
        DIV_OP:
          begin
            if (counter == 0) begin
              current_state <= DIV_POST;
            end
          end
        DIV_POST:
          begin
            current_state <= OUTPUT_RESULT;
          end
        OUTPUT_RESULT:
          begin
            if (i_alu_result_ready && o_alu_result_valid) begin
              current_state <= WAIT_INPUT;
            end
          end
        OUTPUT_ERROR:
          begin
            if (i_alu_result_ready && o_alu_result_valid) begin
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
          input_ready   = 1;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      ADD_OP:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 1;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      SUB_OP:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 1;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      MUL_INIT:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      MUL_OP:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 1;
          in_div        = 0;
          
          reset_counter = 0;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      DIV_FLIP_A:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 1;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      DIV_FLIP_B:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 1;

          in_post_div   = 0;
        end
      DIV_INIT:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      DIV_OP:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 1;
          
          reset_counter = 0;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      DIV_POST:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 0;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 1;
        end
      OUTPUT_RESULT:
        begin
          input_ready   = 0;
          result_valid  = 1;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      OUTPUT_ERROR:
        begin
          input_ready   = 0;
          result_valid  = 1;
          error_flag    = 1;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
      default:
        begin
          input_ready   = 0;
          result_valid  = 0;
          error_flag    = 0;

          in_add        = 0;
          in_sub        = 0;
          in_mul        = 0;
          in_div        = 0;
          
          reset_counter = 1;
          
          flipping_a    = 0;
          flipping_b    = 0;

          in_post_div   = 0;
        end
    endcase
  end
  
  // Data path operations
  always_ff @(posedge clk or negedge rst_n) begin : a_register_block
    if (!rst_n) begin
      a_reg <= '0;
    end else begin
      if (o_alu_input_ready && i_alu_input_valid) begin
        // Load input A
        // A register is wider, fill with zeros at MSBs
        a_reg <= { {(DATA_WIDTH-1){1'b0}}, i_alu_input_a };
      end else if (flipping_a) begin
        // Flip sign of A only when needed
        // flipping_a should only be 1 if i_alu_input_signed is 1
        if (a_reg[DATA_WIDTH-1] == 1'b1) begin
          a_reg[DATA_WIDTH-1:0] <= adder_output;
        end
      end else if (in_mul) begin
        // MUL operation: shift-and-add algorithm (A >> 1)
        a_reg[DATA_WIDTH-1:0] <= { 1'b0, a_reg[DATA_WIDTH-1:1] };
      end else if (in_div) begin
        // DIV operation: 
        if (divides) begin
          // Subtract B from A (A = A - B) // TODO and shift whole thing left
          a_reg <= { adder_output[DATA_WIDTH-2:0], a_reg[DATA_WIDTH-2:0], 1'b0 };
        end else begin
          // Shift left A (A = A << 1)
          a_reg <= { a_reg[2*DATA_WIDTH-3:0], 1'b0 };
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : b_register_block
    if (!rst_n) begin
      b_reg <= '0;
    end else begin
      if (o_alu_input_ready && i_alu_input_valid) begin
        // Load input B
        b_reg <= i_alu_input_b;
      end else if (flipping_b) begin
        // Flip sign of B only when needed
        // flipping_b should only be 1 if i_alu_input_signed is 1
        if (b_reg[DATA_WIDTH-1] == 1'b1) begin
          b_reg <= adder_output;
        end
      end else if (in_mul) begin
        // MUL operation: B shift left by 1
        b_reg <= { b_reg[DATA_WIDTH-2:0], 1'b0 };
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : result_register_block
    if (!rst_n) begin
      result_reg <= '0;
    end else begin
      if (i_alu_input_valid && o_alu_input_ready) begin
        // Clear result reg at input time
        result_reg <= '0;
      end else if (in_add || in_sub) begin
        // ADD/SUB operation: load adder output to result reg
        result_reg <= adder_output;
      end else if (in_mul) begin
        // MUL operation: add B if A[0] is 1
        if (a_reg[0] == 1'b1) begin
          result_reg <= adder_output;
        end
      end else if (in_div) begin
        // DIV operation: shift left and load a bit of 1 if divides, else 0
        result_reg <= { result_reg[DATA_WIDTH-2:0], divides ? 1'b1 : 1'b0 };
      end else if (in_post_div) begin
        // Post-DIV operation: flip sign of result if needed
        if (div_result_neg_reg) begin
          result_reg <= adder_output;
        end
      end
    end
  end

  // Adder inputs selection
  always_comb begin
    // Default assignments
    adder_a_input = '0;
    adder_b_input = '0;
    adder_subtract = 1'b0;

    if (in_add) begin
      // ADD operation
      adder_a_input = a_reg[DATA_WIDTH-1:0];
      adder_b_input = b_reg;
      adder_subtract = 1'b0;
    end else if (in_sub) begin
      // SUB operation
      adder_a_input = a_reg[DATA_WIDTH-1:0];
      adder_b_input = ~b_reg;
      adder_subtract = 1'b1; // Subtract B from A
    end else if (flipping_a) begin
      // Flipping A operation
      adder_a_input = ~a_reg[DATA_WIDTH-1:0];
      adder_b_input = '0;
      adder_subtract = 1'b1; // Add 1 for 2's complement
    end else if (flipping_b) begin
      // Flipping B operation
      adder_a_input = ~b_reg;
      adder_b_input = '0;
      adder_subtract = 1'b1; // Add 1 for 2's complement
    end else if (in_mul) begin
      // MUL operation: add B to lower DATA_WIDTH bits of A
      adder_a_input = result_reg;
      adder_b_input = b_reg;
      adder_subtract = 1'b0;
    end else if (in_div) begin
      // DIV operation: subtract B from upper DATA_WIDTH bits of A
      adder_a_input = a_reg[2*DATA_WIDTH-2:DATA_WIDTH-1];
      adder_b_input = ~b_reg;
      adder_subtract = 1'b1; // Subtract B from A
    end else if (in_post_div) begin
      // Post-DIV operation: flip sign of result if needed
      adder_a_input = result_reg;
      adder_b_input = '0;
      adder_subtract = 1'b1; // Add 1 for 2's complement
    end
  end

  // Counter for multi-cycle operations
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      counter <= '0;
    end else begin
      if (reset_counter) begin
        counter <= COUNTER_WIDTH'(DATA_WIDTH - 1);
      end else if (in_mul || in_div) begin
        counter <= counter - 1;
      end
    end
  end

endmodule