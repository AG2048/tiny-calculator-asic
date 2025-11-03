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

    input  logic [DATA_WIDTH-1:0] i_data,         // Number to be displayed, always ABS value
    input  logic                  i_error,
    input  logic                  i_data_is_neg,  // Indicates if i_data is negative
    input  logic                  i_valid,
    output logic                  o_ready,

    output logic                  o_sr_data,
    output logic                  o_sr_clk,
    output logic                  o_sr_latch,
    output logic                  o_sr_oe_n
);
  /*
    Output driver module that:
      takes in a DATA_WIDTH data input, 
      converts it to 7-seg display format,
      output via shift register interface (o_sr_data, o_sr_clk, o_sr_latch).

    Input follows a valid-ready handshake protocol.
    When (i_valid && o_ready), input data is latched along with i_error bit.
      If i_error is high, display "Err" on 7-seg displays.
      Else, display the value of i_data in HEX format.
    
    Output specifications:
      Output 4 bits per 7-seg display, for NUM_7_SEG_DISPLAYS displays.
      For any bits beyond NUM_7_SEG_DISPLAYS * 4, they are ignored.
      Leading zeros are displayed as blank (no segments lit).
        If i_data_is_neg is high, display a '-' sign on the most significant display. 
        If there's no space to display '-', the most significant digit is replaced with '-'.
      If i_error is high, display "Err" on the displays:
      While displaying: 
        Data is comb logic to be set after rising edge of clk.
        SRCLK begins to pulse with CLK after the data is set.
        After all bits are shifted out, SRLATCH is pulsed high on falling edge of clk. (this is to ensure data is stable before latching)
        OE_n is held low while waiting for new data (output enabled), and set to 1 while new data is being latched (output disabled).
  */
  localparam DISPLAYS_COUNTER_WIDTH = $clog2(NUM_7_SEG_DISPLAYS);
  localparam PER_DISPLAY_COUNTER_WIDTH = 3; // Count from 0 to 6 
  localparam REM = DATA_WIDTH % 4;

  // Assert some parameters
  initial begin
    if (REM != 0)
      $fatal(1, "Parameter DATA_WIDTH (REM=%0d) must be divisible by 4", REM);
    if (NUM_7_SEG_DISPLAYS < 3)
      $fatal(1, "Parameter NUM_7_SEG_DISPLAYS (%0d) must be at least 3", NUM_7_SEG_DISPLAYS);
    if (DATA_WIDTH < 4)
      $fatal(1, "Parameter DATA_WIDTH (%0d) must be at least 4", DATA_WIDTH);
  end


  typedef enum logic [1:0] {
    WAIT_INPUT,
    DISPLAY_VALUE,
    DISPLAY_ERROR,
    LATCH_RESULT
  } output_driver_state_t;

  output_driver_state_t od_current_state;

  // Counters
  logic [DISPLAYS_COUNTER_WIDTH-1:0] display_counter;
  logic [PER_DISPLAY_COUNTER_WIDTH-1:0] per_display_counter;

  // Registers
  logic [DATA_WIDTH-1:0] data_reg;
  logic                  data_is_neg_reg;

  // Comb logic
  logic [DISPLAYS_COUNTER_WIDTH-1:0] highest_display_with_data_index; // Index of highest display that should show ANYTHING
  logic [NUM_7_SEG_DISPLAYS-1:0]     display_data_is_non_zero; // For each display, indicates if that display should show anything (non-zero digit or sign)
  genvar i;
  generate
    // Create a combinational logic block for each display
    for (i = 0; i < NUM_7_SEG_DISPLAYS; i++) begin : display_comb_logic
      if (i * 4 + 4 <= DATA_WIDTH) begin
        // Full 4 bits available
        assign display_data_is_non_zero[i] = |data_reg[i*4 +:4];
      end else if (i * 4 < DATA_WIDTH) begin
        // Partial bits available
        assign display_data_is_non_zero[i] = |data_reg[i*4 +: (DATA_WIDTH - i*4)];
      end else begin
        // No bits available
        assign display_data_is_non_zero[i] = 1'b0;
      end
    end
  endgenerate
  always_comb begin : highest_display_comb_logic
    highest_display_with_data_index = '0;
    for (logic [DISPLAYS_COUNTER_WIDTH-1:0] j = 0; j < NUM_7_SEG_DISPLAYS; j++) begin
      if (display_data_is_non_zero[j]) begin
        highest_display_with_data_index = j;
      end
    end
    if (data_is_neg_reg) begin
      // If negative, add one more for the '-' sign, but don't exceed NUM_7_SEG_DISPLAYS - 1
      if (highest_display_with_data_index == NUM_7_SEG_DISPLAYS - 1) begin
        highest_display_with_data_index = highest_display_with_data_index;
      end else begin
        highest_display_with_data_index = highest_display_with_data_index + 1;
      end
    end
  end

  // Output value decode logic
  logic [6:0] output_sequence; // 7-seg encoding for current digit, [6] being 'a' segment, [0] being 'g' segment (since sub-counter decreases from 6 to 0)
  logic [3:0] output_value_hex; // Current digit value in HEX (4 bits)
  always_comb begin : output_value_decode_comb
    case (output_value_hex)
      // Decode HEX to 7-seg, [6:0] = a,b,c,d,e,f,g, active high
      4'h0: output_sequence = 7'b1111110; // 0
      4'h1: output_sequence = 7'b0110000; // 1
      4'h2: output_sequence = 7'b1101101; // 2
      4'h3: output_sequence = 7'b1111001; // 3
      4'h4: output_sequence = 7'b0110011; // 4
      4'h5: output_sequence = 7'b1011011; // 5
      4'h6: output_sequence = 7'b1011111; // 6
      4'h7: output_sequence = 7'b1110000; // 7
      4'h8: output_sequence = 7'b1111111; // 8
      4'h9: output_sequence = 7'b1111011; // 9
      4'hA: output_sequence = 7'b1110111; // A
      4'hB: output_sequence = 7'b0011111; // b
      4'hC: output_sequence = 7'b1001110; // C
      4'hD: output_sequence = 7'b0111101; // d
      4'hE: output_sequence = 7'b1001111; // E
      4'hF: output_sequence = 7'b1000111; // F
      default: output_sequence = 7'b0000000; // Should never happen
    endcase
  end
  always_comb begin : output_value_hex_comb
    // Determine which 4 bits to output based on display_counter
    if (display_counter * 4 + 4 <= DATA_WIDTH) begin
      // All 4 bits available
      output_value_hex = data_reg[display_counter*4 + 4 - 1 -:4];
    end else begin
      // No bits available
      output_value_hex = 4'b0000;
    end
  end

  // Control signals
  logic sr_clk_enable; // o_sr_clk output enable
  logic latch_enable; // o_sr_latch enable
  logic output_enable_n; // o_sr_oe_n output enable (active low)
  logic output_data; // o_sr_data output data
  logic showing_error; // Indicates if currently displaying error
  logic input_ready;

  logic reset_counters;

  // Output
  assign o_sr_clk = sr_clk_enable ? clk : 1'b1; // Hold high when not enabled so no shifting on first edge
  assign o_sr_latch = latch_enable ? ~clk : 1'b0; // Latch once on falling edge of clock (ensure last bit is shifted in)
  assign o_sr_oe_n = output_enable_n; // Latch once on rising edge
  assign o_sr_data = output_data; // Currently 1 means segment on, and 0 means segment off. Order from MSB to LSB, a,b,c,d,e,f,g
  assign o_ready = input_ready;

  always_ff @(posedge clk) begin : fsm_state_register
    if (!rst_n) begin
      od_current_state <= DISPLAY_VALUE; // Display the zeros on reset
    end else begin
      case (od_current_state)
        WAIT_INPUT: 
          begin
            if (i_valid && o_ready) begin
                // On valid input, move to output state
                od_current_state <= i_error ? DISPLAY_ERROR : DISPLAY_VALUE;
            end
          end
        DISPLAY_VALUE: 
          begin
            // After displaying data, go to latch result
            if (display_counter == 0 && per_display_counter == 0) begin
              od_current_state <= LATCH_RESULT;
            end
          end
        DISPLAY_ERROR: 
          begin
            // After displaying data, go to latch result
            if (display_counter == 0 && per_display_counter == 0) begin
              od_current_state <= LATCH_RESULT;
            end
          end
        LATCH_RESULT: 
          begin
            // Return to wait input after latching result
            od_current_state <= WAIT_INPUT;
          end
        default: 
          begin
            // This should never happen, go to safe state
            od_current_state <= WAIT_INPUT;
          end
      endcase
    end
  end

  // Control signal comb logic
  always_comb begin : fsm_control_signals_comb
    case (od_current_state)
      WAIT_INPUT:
        begin
          sr_clk_enable   = 1'b0;
          latch_enable    = 1'b0;
          output_enable_n = 1'b0;
          reset_counters  = 1'b1;
          showing_error   = 1'b0;
          input_ready     = 1'b1;
        end
      DISPLAY_VALUE:
        begin
          sr_clk_enable   = 1'b1;
          latch_enable    = 1'b0;
          output_enable_n = 1'b1;
          reset_counters  = 1'b0;
          showing_error   = 1'b0;
          input_ready     = 1'b0;
        end
      DISPLAY_ERROR:
        begin
          sr_clk_enable   = 1'b1;
          latch_enable    = 1'b0;
          output_enable_n = 1'b1;
          reset_counters  = 1'b0;
          showing_error   = 1'b1;
          input_ready     = 1'b0;
        end
      LATCH_RESULT:
        begin
          sr_clk_enable   = 1'b0;
          latch_enable    = 1'b1;
          output_enable_n = 1'b0;
          reset_counters  = 1'b0;
          showing_error   = 1'b0;
          input_ready     = 1'b0;
        end
      default:
        begin
          sr_clk_enable   = 1'b0;
          latch_enable    = 1'b0;
          output_enable_n = 1'b1;
          reset_counters  = 1'b1;
          showing_error   = 1'b0;
          input_ready     = 1'b1;
        end
    endcase
  end

  // Registers
  always_ff @(posedge clk) begin : data_registers
    if (!rst_n) begin
      data_reg <= '0;
      data_is_neg_reg <= 1'b0;
    end else begin
      if (i_valid && o_ready) begin
        data_reg <= i_data;
        data_is_neg_reg <= i_data_is_neg;
      end
    end
  end

  // Counters
  always_ff @(posedge clk) begin : counters_ff
    if (!rst_n || reset_counters) begin
      display_counter <= NUM_7_SEG_DISPLAYS - 1;
      per_display_counter <= 6; // Start from segment 'a'
    end else begin
      if (per_display_counter == 0 && display_counter == 0) begin
        per_display_counter <= 6; // Reset all counters
        display_counter <= NUM_7_SEG_DISPLAYS - 1;
      end else if (per_display_counter == 0) begin
        display_counter <= display_counter - 1;
        per_display_counter <= 6;
      end else begin
        per_display_counter <= per_display_counter - 1;
      end
    end
  end

  // Output Data Logic
  always_comb begin : output_data_logic_comb
    if (showing_error) begin
      // Showing Err for error
      if (display_counter == 2) begin
        // Show 'E'
        case (display_counter)
          6: output_data = 1'b1; // a = 1
          5: output_data = 1'b0; // b = 0
          4: output_data = 1'b0; // c = 0
          3: output_data = 1'b1; // d = 1
          2: output_data = 1'b1; // e = 1
          1: output_data = 1'b1; // f = 1
          0: output_data = 1'b1; // g = 1
          default: output_data = 1'b0; // Should never happen
        endcase
      end else if (display_counter == 1 || display_counter == 0) begin
        // Show 'r'
        case (display_counter)
          6: output_data = 1'b0; // a = 0
          5: output_data = 1'b0; // b = 0
          4: output_data = 1'b0; // c = 0
          3: output_data = 1'b0; // d = 0
          2: output_data = 1'b1; // e = 1
          1: output_data = 1'b0; // f = 0
          0: output_data = 1'b1; // g = 1
          default: output_data = 1'b0; // Should never happen
        endcase
      end else begin
        // Other digits blank
        output_data = 1'b0; // All segments off
      end
    end else if (display_counter > highest_display_with_data_index) begin
      // Leading zeros, output blank
      output_data = 1'b0; // All segments off
    end else begin
      // Actual data to display
      if (display_counter == highest_display_with_data_index && data_is_neg_reg) begin
        // Most significant digit is negative sign
        case (display_counter)
          6: output_data = 1'b0; // a = 0
          5: output_data = 1'b0; // b = 0
          4: output_data = 1'b0; // c = 0
          3: output_data = 1'b0; // d = 0
          2: output_data = 1'b0; // e = 0
          1: output_data = 1'b0; // f = 0
          0: output_data = 1'b1; // g = 1 (only segment g on for '-')
          default: output_data = 1'b0; // Should never happen
        endcase
      end else begin
        // Extract 7-seg data for current digit
        output_data = output_sequence[per_display_counter];
      end
    end
  end
endmodule