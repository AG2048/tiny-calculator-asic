`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // Wire for testing signals
  wire [3:0] o_word_lines;
  wire [3:0] i_bit_lines;

  wire [4:0] input_value;

  wire i_add_pin;
  wire i_sub_pin;
  wire i_mul_pin;
  wire i_div_pin;
  wire i_ac_pin;
  wire i_eq_pin;
  wire i_neg_pin;

  wire i_2s_comp_mode_pin;

  wire                  o_add_state_display;
  wire                  o_sub_state_display;
  wire                  o_mul_state_display;
  wire                  o_div_state_display;

  wire                  o_sr_data;
  wire                  o_sr_clk;
  wire                  o_sr_latch;
  wire                  o_sr_oe_n;

  // Assign uio pins direction and unused pins
  assign o_add_state_display = uio_out[0];
  assign o_sub_state_display = uio_out[1];
  assign o_mul_state_display = uio_out[2];
  assign o_div_state_display = uio_out[3];

  assign uio_in[4] = i_eq_pin;
  assign uio_in[5] = i_ac_pin;
  assign uio_in[6] = i_neg_pin;
  assign uio_in[7] = i_2s_comp_mode_pin;

  // Assign signals to Output Pins
  assign o_word_lines = uo_out[3:0];
  assign o_sr_data    = uo_out[4];
  assign o_sr_clk     = uo_out[5];
  assign o_sr_latch   = uo_out[6];
  assign o_sr_oe_n    = uo_out[7];
  
  // Assign Input Pins to signals
  assign      ui_in[3:0] = i_bit_lines;
  assign      ui_in[4]   = i_add_pin;
  assign      ui_in[5]   = i_sub_pin;
  assign      ui_in[6]   = i_mul_pin;
  assign      ui_in[7]   = i_div_pin;

  tt_um_ag2048_tiny_calculator user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule
