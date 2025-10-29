module full_adder #(
  parameter DATA_WIDTH = 16
) (
  input  logic [DATA_WIDTH-1:0] a,
  input  logic [DATA_WIDTH-1:0] b,
  input  logic                  carry_in,
  output logic [DATA_WIDTH-1:0] sum,
  output logic                  carry_out
);
  wire [DATA_WIDTH:0] carry /*verilator split_var*/;

  assign carry_out = carry[DATA_WIDTH];

  assign carry[0] = carry_in;
  for (genvar i = 0; i < DATA_WIDTH; i++) begin : gen_full_adder_bits
    assign sum[i]   = a[i] ^ b[i] ^ carry[i];
    assign carry[i+1] = (a[i] & b[i]) | (carry[i] & (a[i] ^ b[i]));
  end
endmodule