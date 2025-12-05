//==============================================================================
// discrete_r2r_adc.sv
//
// Function:
//   Implements an 8-bit discrete ADC using an external R-2R ladder.
//   Supports two algorithms:
//
//   1) Ramp-compare (original behaviour):
//      - A digital ramp code (0→255) is driven on R2R_out via ramp_waveform.
//      - The external R-2R ladder converts this to an analog ramp V_RAMP.
//      - Comparator compares V_IN vs V_RAMP.
//      - On a falling edge (1→0) of comp_in, we capture the ramp code.
//
//   2) Successive Approximation (SAR):
//      - Uses sar_controller.sv to generate an N-bit code (sar_code).
//      - sar_code directly drives R2R_out and the external ladder.
//      - When sar_controller asserts ready_pulse, we latch sar_code.
//
// Inputs:
//   clk        : System clock.
//   reset      : Active-high synchronous reset; clears all logic.
//   enable     : Enables ADC operation.
//   algo_sar   : 0 = ramp-compare, 1 = SAR.
//   comp_in    : Comparator output.
//
// Outputs:
//   R2R_out      : WIDTH-bit digital code to drive the external R-2R ladder.
//   raw8         : Most recent captured 8-bit ADC code.
//   avg8         : Moving-average filtered version of raw8.
//   scaled_9999  : Filtered ADC code scaled into 0-9999 (≈ millivolts).
//   ready_pulse  : 1-clock-wide strobe when a new conversion is captured.
//
// Parameters:
//   WIDTH        : Resolution of ADC (default = 8 bits).
//
// Notes:
//   • comp_in is synchronized for ramp-compare edge detection.
//   • sar_controller handles comparator timing for SAR mode internally.
//==============================================================================

module discrete_r2r_adc #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             reset,
    input  logic             enable,
    input  logic             algo_sar,    // 0 = ramp, 1 = SAR
    input  logic             comp_in,     // comparator output

    output logic [WIDTH-1:0] R2R_out,     // to external R-2R ladder
    output logic [WIDTH-1:0] raw8,
    output logic [WIDTH-1:0] avg8,
    output logic [15:0]      scaled_9999,
    output logic             ready_pulse
);

    //==================================================================
    // 1) Comparator synchronization for ramp-compare mode
    //    (SAR uses comp_in inside sar_controller.sv)
    //==================================================================
    logic comp_meta;   // first synchronizer stage
    logic comp_sync;   // second synchronizer stage (clean)
    logic comp_prev;   // previous synchronized value

    always_ff @(posedge clk) begin
        if (reset) begin
            comp_meta <= 1'b0;
            comp_sync <= 1'b0;
            comp_prev <= 1'b0;
        end else begin
            comp_meta <= comp_in;    // async input -> meta
            comp_sync <= comp_meta;  // meta -> synced
            comp_prev <= comp_sync;  // save previous synced value
        end
    end

    // Falling-edge detection (1->0) for ramp-compare mode
    logic ready_ramp;
    assign ready_ramp = (~comp_sync & comp_prev) && enable && !algo_sar;

    //==================================================================
    // 2) Ramp generator (only active in ramp-compare mode)
    //==================================================================
    logic               dummy_pwm;
    logic [WIDTH-1:0]   ramp_code;

    ramp_waveform #(
        .WIDTH        (WIDTH),
        .WAVE_FREQ_HZ (5)
    ) u_ramp (
        .clk     (clk),
        .reset   (reset),
        .enable  (enable && !algo_sar),
        .pwm_out (dummy_pwm), // unused for R-2R path
        .R2R_out (ramp_code)
    );

    //==================================================================
    // 3) SAR path: use existing sar_controller to generate sar_code
    //==================================================================
    logic [WIDTH-1:0] sar_code;
    logic             ready_sar;

    sar_controller #(
        .WIDTH(WIDTH),
        .SETTLE_CYCLES(1000000)
        // Use whatever SETTLE_CYCLES parameter you defined inside sar_controller
    ) u_sar (
        .clk         (clk),
        .reset       (reset),
        .enable      (enable && algo_sar),
        .comp_in     (comp_in),
        .dac_code    (sar_code),
        .ready_pulse (ready_sar)
    );

    //==================================================================
    // 4) Select active algorithm (ramp vs SAR) for code, ready, and R2R_out
    //==================================================================
    logic [WIDTH-1:0] active_code;
    logic             active_ready;

    always_comb begin
        if (algo_sar) begin
            // SAR mode
            active_code  = sar_code;
            active_ready = ready_sar;
        end else begin
            // Ramp-compare mode
            active_code  = ramp_code;
            active_ready = ready_ramp;
        end
    end

    assign R2R_out    = active_code;
    assign ready_pulse = active_ready;

    //==================================================================
    // 5) Latch raw code on new conversion (shared for both modes)
    //==================================================================
    always_ff @(posedge clk) begin
        if (reset)
            raw8 <= '0;
        else if (active_ready)
            raw8 <= active_code;
    end

    //==================================================================
    // 6) Average and scale
    //==================================================================

    // Moving average over 2^2 = 4 samples (reduces jitter, still responsive)
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

    // Scale avg8 (0..255) to 0..9999
    scaler8_to_9999 u_scale (
        .clk    (clk),
        .reset  (reset),
        .en     (active_ready),
        .code8  (avg8),
        .scaled (scaled_9999)
    );

endmodule
