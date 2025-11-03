/*
 * Copyright (c) 2025 Andy Gong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module button_reader (
    input  logic       clk,
    input  logic       rst_n,

    output logic [3:0] o_word_lines,
    input  logic [3:0] i_bit_lines,

    input  logic       i_ac_pin,
    input  logic       i_add_pin,
    input  logic       i_sub_pin,
    input  logic       i_mul_pin,
    input  logic       i_div_pin,
    input  logic       i_eq_pin,
    input  logic       i_neg_pin,

    output logic [4:0] o_data,
    output logic       o_valid,
    input  logic       i_ready
);
  /* 
    Button reader module, scans a 4x4 button matrix plus 6 operation buttons.
    Initiates a counter that writes to the word lines, and read the bit lines to detect button presses.
    On the key pad matrix, the last column is prioritized, so if multiple buttons are pressed in the same row, the rightmost button is recorded.
    Operation buttons are prioritized over number buttons. (with ADD being the highest priority)

    When a button press is detected, the module keeps scanning until all buttons are released for a full scan cycle, while the cycle before that had a button press detected.
    Then the last-recorded button press is output with o_valid high.
    The module waits for i_ready to be high before accepting new button presses.

    When o_valid high, no button presses are recorded. 

    To determine if a button press has occurred in this cycle, we check a button_pressed_reg at the clock edge when counter == 0.
    This register is set if any button press is detected. Only reset when counter is 00 and no button press is detected.
    A prev_button_pressed_reg is also used to indicate if a button press was recorded in the previous cycle.
    This register is set to button_pressed_reg at counter == 00 (indicating some button press was recorded in previous cycle)
    Both registers are reset when o_valid is high (indicating no button press will be recorded).

    Output register is not updated when o_valid is high, or when no button press is detected.
    Due to the chance of button press exactly at counter == 00 after a press-release cycle (where o_valid becomes high at next rising edge), 
    the output register is also not updated when enable_o_valid is high (indicating o_valid will be set high at next rising edge).
  */

  // Decoding logic for word lines scanning
  logic [1:0] counter;
  logic [3:0] number_input;
  always_comb begin : decode_number_input
    // Assign upper 2 bits to match counter
    number_input[3:2] = counter[1:0];

    // Assign lower 2 bits based on bit lines
    casez (i_bit_lines)
      // Using casez to ignore irrelevant bits
      4'b1???: number_input[1:0] = 2'b11; // 3
      4'b01??: number_input[1:0] = 2'b10; // 2
      4'b001?: number_input[1:0] = 2'b01; // 1
      4'b0001: number_input[1:0] = 2'b00; // 0
      default: number_input[1:0] = 2'b00; // No button pressed
    endcase
  end

  // Decoding operation buttons 
  logic [2:0] op_input;
  logic     op_button_pressed;
  assign op_button_pressed = i_ac_pin || i_add_pin || i_sub_pin ||
                             i_mul_pin || i_div_pin || i_eq_pin || i_neg_pin;
  always_comb begin : decode_op_input
    op_input = 3'b000;
    if      (i_add_pin) op_input = 3'b000; // +
    else if (i_sub_pin) op_input = 3'b001; // -
    else if (i_mul_pin) op_input = 3'b010; // *
    else if (i_div_pin) op_input = 3'b011; // /
    else if (i_eq_pin)  op_input = 3'b100; // =
    else if (i_ac_pin)  op_input = 3'b101; // AC
    else if (i_neg_pin) op_input = 3'b110; // Negative
  end

  // 2-bit counter to scan the 4 word lines in sequence
  // Always counting up
  always_ff @(posedge clk) begin : word_line_counter
    if (!rst_n) begin
      counter <= 2'b00;
    end else begin
      counter[0] <= ~counter[0];
      counter[1] <= counter[0] ? ~counter[1] : counter[1];
    end
  end

  // Decode counter to word lines output
  assign o_word_lines = counter[1] ? (counter[0] ? 4'b1000 : 4'b0100) : 
                                     (counter[0] ? 4'b0010 : 4'b0001);

  // Logic to check if any button press is detected
  logic any_button_pressed;
  assign any_button_pressed = (i_bit_lines != 4'b0000) ||
                              i_ac_pin || i_add_pin || i_sub_pin ||
                              i_mul_pin || i_div_pin || i_eq_pin || i_neg_pin;

  // Register to retain if a button press is made in the current scan cycle
  // (A button press occurred in previous cycle if value is 1 at counter == 0)
  // This value is forced to 0 when data is valid
  logic button_pressed_reg;
  always_ff @(posedge clk) begin : button_pressed_register
    if (!rst_n) begin
      button_pressed_reg <= 1'b0;
    end else begin
      if (o_valid) begin
        // Force 0 to indicate no button will be recorded
        // equivalent to no button pressed
        button_pressed_reg <= 1'b0;
      end else if (counter == 2'b00) begin
        button_pressed_reg <= any_button_pressed;
      end else begin
        button_pressed_reg <= button_pressed_reg || any_button_pressed;
      end
    end
  end

  // Register to retain if a previous cycle button press has been recorded
  // This value is forced to 0 when data is valid
  // This register is an indicator that there's currently a valid button value stored in the output register
  logic prev_button_pressed_reg;
  always_ff @(posedge clk) begin : prev_button_pressed_register
    if (!rst_n) begin
      prev_button_pressed_reg <= 1'b0;
    end else begin
      if (o_valid) begin
        // Force 0 to indicate no button presses in previous cycle would be recorded
        // equivalent to no button pressed in previous cycle
        prev_button_pressed_reg <= 1'b0;
      end else if (button_pressed_reg && (counter == 2'b00)) begin
        prev_button_pressed_reg <= 1'b1;
      end
    end
  end

  // Logic to turn on data valid output
  // (When no button pressed in current cycle, but previous cycle had a button press)
  // (On all button release)
  logic enable_o_valid;
  assign enable_o_valid = counter == 2'b00 &&
                          !button_pressed_reg &&
                          prev_button_pressed_reg;

  // Output data register
  logic [4:0] o_data_reg;
  always_ff @(posedge clk) begin : output_data_register
    if (!rst_n) begin
      o_data_reg <= 5'b00000;
    end else begin
      if (!o_valid && !enable_o_valid) begin
        // Update data only when not valid, and not enabling valid
        if (op_button_pressed) begin
          o_data_reg <= {2'b10, op_input}; // Operation buttons have MSB = 1
        end else if (any_button_pressed) begin
          o_data_reg <= {1'b0, number_input}; // Number buttons have MSB = 0
        end
      end
    end
  end
  assign o_data = o_data_reg;

  // Data valid output register
  logic o_valid_reg;
  always_ff @(posedge clk) begin : output_valid_register
    if (!rst_n) begin
      o_valid_reg <= 1'b0;
    end else begin
      if (i_ready && o_valid) begin
        o_valid_reg <= 1'b0;
      end else if (enable_o_valid) begin
        o_valid_reg <= 1'b1;
      end
    end
  end
  assign o_valid = o_valid_reg;

endmodule
