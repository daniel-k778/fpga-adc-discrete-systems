//==============================================================================
// scaler8_to_9999.sv
//
// Function:
//   Scales an 8-bit value (0-255) into a 4-digit 0-9999 range using fixed-point
//   arithmetic. This is used to convert a discrete ADC code into a value
//   suitable for seven-segment decimal display.
//
// Theory:
//     scaled ≈ (code8 / 255) * 9999
//
//   To avoid a hardware divider, the expression is implemented with a
//   fixed-point multiply and bit-shift using the approximation:
//
//     9999/255 ≈ FACTOR / 2^SHIFT
//     FACTOR = round((9999/255)*2^15) = 1,284,891
//     SHIFT  = 15
//
//   Thus:
//
//     scaled = (code8 * FACTOR) >> SHIFT
//
// Inputs:
//   clk     : System clock.
//   reset   : Active-high synchronous reset; clears internal registers.
//   en      : Enable strobe; when high, latches new input and updates output.
//   code8   : 8-bit averaged ADC code (0-255).
//
// Outputs:
//   scaled  : 16-bit scaled value (0-9999) for display/UI use.
//
// Notes:
//   • Used by both discrete PWM and R-2R ADC paths in Lab 7.
//   • Keeps output stable between enable strobes to avoid flicker.
//   • Truncation keeps hardware small while retaining display precision.
//
//==============================================================================

module scaler8_to_9999(
    input  logic       clk,
    input  logic       reset,
    input  logic       en,       // latch on strobe
    input  logic [7:0] code8,
    output logic [15:0] scaled
);
    localparam int FACTOR = 1284891;
    localparam int SHIFT  = 15;

    logic [31:0] prod;
    always_ff @(posedge clk) begin
        if (reset) begin
            prod   <= 32'd0;
            scaled <= 16'd0;
        end else if (en) begin
            prod   <= code8 * FACTOR;
            scaled <= prod[SHIFT +: 16]; // (prod >> SHIFT) truncated to 16 bits
        end
    end
endmodule
