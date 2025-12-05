//==============================================================================
// code8_to_mV.sv
//
// Function:
//   Converts an averaged 8-bit discrete ADC code (0-255) into millivolts
//   (0-3300 mV range) using fixed-point integer arithmetic. The output event
//   is synchronized to a 1-cycle enable strobe.
//
// Theory:
//     VIN ≈ (code_in / 255) * 3300 mV
//
//   Direct division by 255 is inefficient in hardware, so we approximate:
//
//     3300/255 ≈ 3313/256
//
//   Which gives:
//
//     mV_out ≈ (code_in * 3313) >> 8
//
//   Using a 24-bit constant ensures enough precision in multiplication so that
//   shifting right by 8 bits produces a full 0-3300 mV result without overflow.
//
// Inputs:
//   clk      : System clock.
//   reset    : Active-high synchronous reset; clears output.
//   en       : Strobe indicating new averaged ADC code available.
//   code_in  : Averaged 8-bit ADC result (0-255).
//
// Output:
//   mV_out   : Scaled 16-bit millivolt value (0-3300 typical).
//
// Notes:
//   • Only updates output on en pulses to preserve stable readings.
//   • Used by discrete PWM ADC and R-2R ADC paths in Lab 7.
//   • Small, purely combinational math wrapped in synchronous latch.
//
//==============================================================================

module code8_to_mV (
    input  logic        clk,
    input  logic        reset,
    input  logic        en,          // strobe when new averaged code is ready
    input  logic [7:0]  code_in,     // averaged 8-bit ADC code
    output logic [15:0] mV_out       // scaled millivolts (0..3300)
);
    always_ff @(posedge clk) begin
        if (reset) begin
            mV_out <= '0;
        end
        else if (en) begin
            // 24-bit multiply by 3313 then >> 8 (divide by 256)
            mV_out <= (code_in * 24'd3313) >> 8;
        end
    end
endmodule
