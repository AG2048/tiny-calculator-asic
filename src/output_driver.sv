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
    output logic                  o_sr_oe_n
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
  localparam DISPLAYS_COUNTER_WIDTH = $clog2(NUM_7_SEG_DISPLAYS);
  localparam PER_DISPLAY_COUNTER_WIDTH = 3; // Count from 0 to 6 

// TODO: remove these: Temp assign all input to 0, tie all output to ^ _unused
logic temp = ^{clk, rst_n, i_data, i_error, i_data_is_neg, i_valid};
assign o_sr_data  = temp;
assign o_sr_clk   = temp;
assign o_sr_latch = temp;
assign o_ready    = temp;

  typedef enum logic [2:0] {
    LOAD_INPUT,
    CLEAR_OUTPUT,
    DISPLAY_DATA,
    DISPLAY_ERROR,
    OUTPUT_DONE
  } output_driver_state_t;

  output_driver_state_t current_state;

  // Counters
  logic [DISPLAYS_COUNTER_WIDTH-1:0] display_counter;
  logic [PER_DISPLAY_COUNTER_WIDTH-1:0] per_display_counter;

  // Registers
  logic [DATA_WIDTH-1:0] data_reg;
  logic                  data_is_neg_reg;
  logic                  error_reg;

  // Control signals
  logic oe; // o_sr_clk output enable
  logic latch_en; // o_sr_latch enable

  // Output
  assign o_sr_clk = oe ? clk : 1'b1; // Since shift register shifts on rising edge, hold clk high to prevent shifting
  assign o_sr_latch = latch_en; // Latch once on rising edge


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= LOAD_INPUT;
    end else begin
      case (current_state)
        LOAD_INPUT: 
          begin
            if (i_valid && o_ready) begin
                // On valid input, move to clear output state
                current_state <= CLEAR_OUTPUT;
            end
          end
        CLEAR_OUTPUT: 
          begin
            // After clearing output, go back to loading input
            if (display_counter == 0 && per_display_counter == 0) begin
              current_state <= error_reg ? DISPLAY_ERROR : DISPLAY_DATA;
            end
          end
        DISPLAY_DATA: 
          begin
            // After displaying data, go back to loading input
            if (display_counter == 0 && per_display_counter == 0) begin
              current_state <= OUTPUT_DONE;
            end
          end
        DISPLAY_ERROR: 
          begin
            // After displaying error, go back to loading input
            if (display_counter == 0 && per_display_counter == 0) begin
              current_state <= OUTPUT_DONE;
            end
          end
        OUTPUT_DONE:
          begin
            // After output done, go back to loading input
            current_state <= LOAD_INPUT;
          end 
        default: 
          begin
            current_state <= LOAD_INPUT;
          end
      endcase
    end
  end

endmodule