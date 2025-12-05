//==============================================================================
// discrete_pwm_adc.sv
//
// Function:
//   Implements an 8-bit discrete ADC using a PWM-generated DAC.
//   Supports two algorithms:
//
//   1) Ramp-compare (original behaviour):
//      - The PWM duty cycle increases monotonically 0→255 via ramp_waveform.
//      - After the RC low-pass filter, this becomes an analog ramp V_RAMP.
//      - Comparator compares V_IN vs V_RAMP.
//      - On a falling edge of the comparator output, we capture the ramp code.
//
//   2) Successive Approximation (SAR):
//      - Uses external sar_controller.sv to generate a DAC code (sar_code).
//      - A simple carrier counter + compare implements the PWM DAC.
//      - When sar_controller asserts ready_pulse, we latch sar_code.
//
// Inputs:
//   clk        : System clock.
//   reset      : Active-high reset.
//   enable     : Enables ADC operation.
//   algo_sar   : 0 = ramp-compare, 1 = SAR mode.
//   comp_in    : Comparator output (polarity must match sar_controller).
//
// Outputs:
//   pwm_out      : PWM drive output → RC filter → analog V_DAC.
//   raw8         : Most recent captured 8-bit ADC code.
//   avg8         : Moving-average filtered version of raw8.
//   scaled_9999  : Filtered ADC code scaled into 0-9999 (≈ millivolts).
//   ready_pulse  : 1-clock-wide strobe when a new conversion is captured.
//
// Parameters:
//   WIDTH            : Resolution of ramp/ADC (default = 8 bits).
//
// Notes:
//   • For ramp mode, we still use edge-detect on a synchronized comp_in.
//   • For SAR mode, sar_controller internally handles comparator timing.
//==============================================================================

module discrete_pwm_adc #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             reset,
    input  logic             enable,
    input  logic             algo_sar,    // 0 = ramp, 1 = SAR
    input  logic             comp_in,     // comparator output

    output logic             pwm_out,
    output logic [WIDTH-1:0] raw8,        // last captured code
    output logic [WIDTH-1:0] avg8,        // moving average of raw8
    output logic [15:0]      scaled_9999, // 0..9999 (≈ mV)
    output logic             ready_pulse  // 1-cycle strobe on new capture
);

    //==================================================================
    // 1) Comparator synchronization for ramp-compare edge detect
    //     (SAR uses its own logic inside sar_controller.sv)
    //==================================================================
    logic comp_meta;   // first synchronizer stage
    logic comp_sync;   // second synchronizer stage (cleaned)
    logic comp_prev;   // previous synchronized value

    always_ff @(posedge clk) begin
        if (reset) begin
            comp_meta <= 1'b0;
            comp_sync <= 1'b0;
            comp_prev <= 1'b0;
        end else begin
            comp_meta <= comp_in;    // async input -> meta
            comp_sync <= comp_meta;  // meta -> synced
            comp_prev <= comp_sync;  // delayed synced value
        end
    end

    // Falling-edge detection (1->0) for ramp-compare mode
    logic ready_ramp;
    assign ready_ramp = (~comp_sync & comp_prev) && enable && !algo_sar;

    //==================================================================
    // 2) Ramp-compare path: ramp_waveform as before
    //==================================================================
    logic [WIDTH-1:0] ramp_code;
    logic             pwm_ramp;

    ramp_waveform #(
        .WIDTH        (WIDTH),
        .WAVE_FREQ_HZ (5)
    ) u_ramp (
        .clk     (clk),
        .reset   (reset),
        .enable  (enable && !algo_sar),
        .pwm_out (pwm_ramp),
        .R2R_out (ramp_code)
    );

    //==================================================================
    // 3) SAR path: sar_controller + simple PWM DAC
    //==================================================================
    logic [WIDTH-1:0] sar_code;
    logic             ready_sar;

    // Your existing SAR controller module
    sar_controller #(
        .WIDTH(WIDTH),
        .SETTLE_CYCLES(1000000)
        // SETTLE_CYCLES parameter is inside sar_controller.sv you already have
    ) u_sar (
        .clk         (clk),
        .reset       (reset),
        .enable      (enable && algo_sar),
        .comp_in     (comp_in),
        .dac_code    (sar_code),
        .ready_pulse (ready_sar)
    );

    // Simple PWM DAC driven by sar_code
    logic [WIDTH-1:0] carrier;
    logic             pwm_sar;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            carrier <= '0;
        end else if (enable && algo_sar) begin
            carrier <= carrier + 1'b1;
        end else if (!enable || !algo_sar) begin
            carrier <= '0;
        end
    end

    assign pwm_sar = (enable && algo_sar) ? (carrier < sar_code) : 1'b0; // duty cycle

    //==================================================================
    // 4) Select between algorithms (ramp vs SAR)
    //==================================================================
    logic [WIDTH-1:0] active_code;
    logic             active_ready;

    always_comb begin
        if (algo_sar) begin
            // SAR mode
            active_code  = sar_code;
            active_ready = ready_sar;
            pwm_out      = pwm_sar;
        end else begin
            // Ramp-compare mode
            active_code  = ramp_code;
            active_ready = ready_ramp;
            pwm_out      = pwm_ramp;
        end
    end

    assign ready_pulse = active_ready;

    //==================================================================
    // 5) Latch raw code (shared for both algorithms)
    //==================================================================
    always_ff @(posedge clk) begin
        if (reset)
            raw8 <= '0;
        else if (active_ready)
            raw8 <= active_code;
    end

    //==================================================================
    // 6) Moving average over 2^2 = 4 samples
    //==================================================================
    averager #(
        .power (2),
        .N     (WIDTH)
    ) u_avg (
        .clk   (clk),
        .reset (reset),
        .EN    (active_ready),
        .Din   (raw8),
        .Q     (avg8)
    );

    //==================================================================
    // 7) Scale avg8 to 0..9999
    //==================================================================
    scaler8_to_9999 u_scale (
        .clk    (clk),
        .reset  (reset),
        .en     (active_ready),
        .code8  (avg8),
        .scaled (scaled_9999)
    );

endmodule
