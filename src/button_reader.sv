/*
 * Copyright (c) 2024 Andy Gong
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

    output logic [4:0] o_data,
    output logic       o_data_valid,
    input  logic       i_read_ready
);
    // Decoding logic for word lines scanning
    logic [1:0] counter;
    logic [3:0] number_input;
    assign number_input[3:2] = counter[1:0];
    always_comb begin
        case (i_bit_lines)
            4'b1???: number_input[1:0] = 2'b11; // 3
            4'b01??: number_input[1:0] = 2'b10; // 2
            4'b001?: number_input[1:0] = 2'b01; // 1
            4'b0001: number_input[1:0] = 2'b00; // 0
            default: number_input[1:0] = 2'b00; // No button pressed
        endcase
    end

    // Decoding operation buttons 
    logic [2:0] op_input;
    logic       op_button_pressed;
    assign op_button_pressed = i_ac_pin || i_add_pin || i_sub_pin ||
                               i_mul_pin || i_div_pin || i_eq_pin;
    always_comb begin
        op_input = 3'b000;
        if (i_ac_pin) op_input = 3'b000; // AC
        else if (i_add_pin) op_input = 3'b001; // +
        else if (i_sub_pin) op_input = 3'b010; // -
        else if (i_mul_pin) op_input = 3'b011; // *
        else if (i_div_pin) op_input = 3'b100; // /
        else if (i_eq_pin)  op_input = 3'b101; // =
    end

    // 2-bit counter to scan the 4 word lines in sequence
    // Always counting up
    always_ff @(posedge clk or negedge rst_n) begin
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
                         i_mul_pin || i_div_pin || i_eq_pin;

    // Register to retain if a button press is made in the current scan cycle
    // (A button press occurred in previous cycle if value is 1 at counter == 0)
    logic button_pressed_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            button_pressed_reg <= 1'b0;
        end else begin
            if (counter == 2'b00) begin
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
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_button_pressed_reg <= 1'b0;
        end else begin
            if (o_data_valid) begin
                prev_button_pressed_reg <= 1'b0;
            end else if (button_pressed_reg && (counter == 2'b00)) begin
                prev_button_pressed_reg <= 1'b1;
            end
        end
    end

    // Logic to turn on data valid output
    // (When no button pressed in current cycle, but previous cycle had a button press)
    // (On all button release)
    logic enable_data_valid;
    assign enable_data_valid = counter == 2'b00 &&
                               !button_pressed_reg &&
                               prev_button_pressed_reg;

    // Output data register
    logic [4:0] data_read_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_read_reg <= 5'b00000;
        end else begin
            if (!o_data_valid && !enable_data_valid) begin
                // Update data only when not valid, and not enabling valid
                if (op_button_pressed) begin
                    data_read_reg <= {2'b10, op_input}; // Operation buttons have MSB = 1
                end else if (any_button_pressed) begin
                    data_read_reg <= {1'b0, number_input}; // Number buttons have MSB = 0
                end
            end
        end
    end
    assign o_data = data_read_reg;

    // Data valid output register
    logic data_valid_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_valid_reg <= 1'b0;
        end else begin
            if (i_read_ready && o_data_valid) begin
                data_valid_reg <= 1'b0;
            end else if (enable_data_valid) begin
                data_valid_reg <= 1'b1;
            end
        end
    end
    assign o_data_valid = data_valid_reg;

endmodule
