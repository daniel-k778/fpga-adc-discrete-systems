//==============================================================================
// ramp_waveform.sv
//
// Function:
//   Generates a repeating digital ramp and corresponding PWM signal.
//   - The digital ramp (R2R_out) counts from 0 to 2^WIDTH-1 and then wraps.
//   - The PWM output (pwm_out) has duty cycle proportional to the ramp value.
//   - Together, these can be used to create an analog ramp:
//       • pwm_out + RC low-pass filter → analog ramp (PWM DAC)
//       • R2R_out + external R-2R ladder → analog ramp (parallel DAC)
//
//   The update rate of the ramp is controlled by WAVE_FREQ_HZ.
//   When enable = 0, outputs are forced low if ZERO_WHEN_DISABLED is set.
//
// Inputs:
//   clk   : System clock (e.g., 100 MHz).
//   reset : Asynchronous reset, active high. Clears counters and outputs.
//   enable: Enables ramp and PWM generation when high. When low, the ramp and
//           carrier stop advancing; outputs can be forced to 0.
//
// Outputs:
//   pwm_out : PWM signal whose duty cycle increases as the ramp increases.
//             Used with an RC filter to generate an analog ramp voltage.
//   R2R_out : WIDTH-bit digital ramp value (0 .. 2^WIDTH-1).
//             Typically drives an external R-2R ladder DAC.
//
// Parameters:
//   WIDTH             : Number of bits in the ramp/DAC code (default 8).
//   CLOCK_FREQ        : Input clock frequency in Hz (default 100 MHz).
//   WAVE_FREQ_HZ      : Desired ramp repeat rate in Hz (full ramp period).
//   ZERO_WHEN_DISABLED: If 1, forces outputs and internal counters to 0
//                       when enable = 0.
//
//==============================================================================

module ramp_waveform #(
    parameter int WIDTH          = 8,             // Bits of the ramp/DAC
    parameter int CLOCK_FREQ     = 100_000_000,   // CLK Frequency
    parameter int WAVE_FREQ_HZ   = 1,             // RAMP Frequency
    parameter bit ZERO_WHEN_DISABLED = 1          // Force outputs low when disabled
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               enable,
    output logic               pwm_out,           // PWM whose duty = ramp level
    output logic [WIDTH-1:0]   R2R_out            // Parallel code for R-2R DAC
);

    // How often to step the ramp
    localparam int unsigned STEPS           = (1 << WIDTH);
    localparam int unsigned TICKS_PER_STEP0 = (WAVE_FREQ_HZ == 0) ? 1 : (CLOCK_FREQ / (WAVE_FREQ_HZ * STEPS));
    localparam int unsigned TICKS_PER_STEP  = (TICKS_PER_STEP0 == 0) ? 1 : TICKS_PER_STEP0;
    localparam int unsigned STEP_DIV_WIDTH  = (TICKS_PER_STEP <= 1) ? 1 : $clog2(TICKS_PER_STEP);

    logic [WIDTH-1:0] ramp;
    logic [WIDTH-1:0] carrier;
    logic [STEP_DIV_WIDTH-1:0] step_div;

    logic step_tick;
    assign step_tick = (step_div == TICKS_PER_STEP-1);

    // Step counter
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            step_div <= '0;
        else if (enable)
            step_div <= step_tick ? '0 : (step_div + 1'b1);
        else if (ZERO_WHEN_DISABLED)
            step_div <= '0;
    end

    // Ramp value (0..255 then wrap)
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            ramp <= '0;
        else if (enable && step_tick)
            ramp <= ramp + 1'b1;    // wrap by overflow
        else if (!enable && ZERO_WHEN_DISABLED)
            ramp <= '0;
    end

    // High-frequency sawtooth for PWM comparison
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            carrier <= '0;
        else if (enable)
            carrier <= carrier + 1'b1;
        else if (ZERO_WHEN_DISABLED)
            carrier <= '0;
    end

    // PWM compare + DAC output
    assign pwm_out = enable && (carrier < ramp);// duty cycle
    assign R2R_out = enable ? ramp : '0;

endmodule
