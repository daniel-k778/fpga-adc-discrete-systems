//==============================================================================
// Module: averager
//
// Function:
//   Implements a moving-average filter over a sliding window of 2^power samples.
//   Used to reduce jitter / noise in discrete ADC readings by smoothing
//   multiple conversion results. Each new input sample replaces the oldest,
//   maintaining a continuous running average.
//
// Operation:
//   • REG_ARRAY stores the last 2^power input samples
//   • sum holds the running total of those samples
//   • Output Q is computed as:  sum >> power   (divide by 2^power)
//   • On each enable pulse (EN = 1), a new value is inserted and the oldest
//     is removed from sum - avoiding expensive full recomputation.
//
// Inputs:
//   clk   : System clock.
//   reset : Active-high synchronous reset; clears sum and history buffer.
//   EN    : Enable strobe for updating with a new sample.
//   Din   : New input sample, N bits wide.
//
// Output:
//   Q     : Moving-average result, N bits wide (top bits of scaled sum).
//
// Parameters:
//   power : Window size exponent → number of samples averaged = 2^power.
//   N     : Bit-width of input and output samples.
//
// Notes:
//   • Window size is tunable trade-off between noise filtering and latency.
//   • Works entirely in integer arithmetic, efficiently synthesized.
//
//==============================================================================

module averager
    #(parameter int
        power = 8, // 2**N samples, default is 2**8 = 256 samples
        N = 12)    // # of bits to take the average of
    (
        input logic clk,
        reset,
        EN,
        input logic [N-1:0] Din,   // input to averager
        output logic [N-1:0] Q     // N-bit moving average
    );

    logic [N-1:0] REG_ARRAY [2**power:1];
    logic [power+N-1:0] sum;
    assign Q = sum[power+N-1:power];

    always_ff @(posedge clk) begin
        if (reset) begin
            sum <= 0;
            for (int j = 1; j <= 2**power; j++) begin
                REG_ARRAY[j] <= 0;
            end
        end
        else if (EN) begin
            sum <= sum + Din - REG_ARRAY[2**power];
            for (int j = 2**power; j > 1; j--) begin
                REG_ARRAY[j] <= REG_ARRAY[j-1];
            end
            REG_ARRAY[1] <= Din;
        end
    end
endmodule
