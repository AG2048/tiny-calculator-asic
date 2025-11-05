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
  // Internal signal declarations
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
  assign uio_oe             = 8'b00111100;          // uio[2:5] are outputs, others are inputs
  assign uio_out[1:0]       = 2'b00;                // Unused output pins
  assign uio_out[2]         = o_add_state_display;
  assign uio_out[3]         = o_sub_state_display;
  assign uio_out[4]         = o_mul_state_display;
  assign uio_out[5]         = o_div_state_display;
  assign uio_out[7:6]       = 2'b00;                // Unused output pins

  assign i_ac_pin           = uio_in[0];
  assign i_eq_pin           = uio_in[1];
  assign i_2s_comp_mode_pin = uio_in[6];
  assign i_neg_pin          = uio_in[7];
  wire   _unused            = &{uio_in[5:2], ena, 1'b0}; // Prevent unused input warnings

  // Assign signals to Output Pins
  assign uo_out[3:0] = o_word_lines;
  assign uo_out[4]   = o_sr_data;
  assign uo_out[5]   = o_sr_clk;
  assign uo_out[6]   = o_sr_latch;
  assign uo_out[7]   = o_sr_oe_n;
  
  // Assign Input Pins to signals
  assign i_bit_lines        = ui_in[3:0];
  assign i_add_pin          = ui_in[4];
  assign i_sub_pin          = ui_in[5];
  assign i_mul_pin          = ui_in[6];
  assign i_div_pin          = ui_in[7];

  tt_um_ag2048_calculator user_project (

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
