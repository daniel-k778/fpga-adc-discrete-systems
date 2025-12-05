//==============================================================================
// adc_auto_calib.sv
//
// Simple 1-point auto-calibration.
// When cal_btn is pressed, capture the current XADC reading (ref_mV)
// and the current discrete readings (pwm_mV, r2r_mV). Compute and store
// offsets so that in steady state:
//
//   pwm_mV_corr ≈ ref_mV
//   r2r_mV_corr ≈ ref_mV
//
// Offsets are applied to all future readings until reset or next calibration.
//==============================================================================

module adc_auto_calib (
    input  logic        clk,
    input  logic        reset,

    // trigger
    input  logic        cal_btn,        // raw pushbutton

    // current measurements (unsigned 0..~3300)
    input  logic [15:0] ref_mV,         // from XADC
    input  logic [15:0] pwm_mV,         // from PWM ADC
    input  logic [15:0] r2r_mV,         // from R2R ADC

    // corrected outputs
    output logic [15:0] pwm_mV_corr,
    output logic [15:0] r2r_mV_corr
);

    // --- 1) Synchronize + edge-detect button ---
    logic btn_meta, btn_sync, btn_prev;
    logic cal_pulse;

    always_ff @(posedge clk) begin
        if (reset) begin
            btn_meta <= 1'b0;
            btn_sync <= 1'b0;
            btn_prev <= 1'b0;
        end else begin
            btn_meta <= cal_btn;
            btn_sync <= btn_meta;
            btn_prev <= btn_sync;
        end
    end

    assign cal_pulse = btn_sync & ~btn_prev;   // rising-edge 1-cycle pulse

    // --- 2) Store signed offsets when calibration is triggered ---
    logic signed [15:0] off_pwm, off_r2r;

    always_ff @(posedge clk) begin
        if (reset) begin
            off_pwm <= '0;
            off_r2r <= '0;
        end else if (cal_pulse) begin
            off_pwm <= $signed(ref_mV) - $signed(pwm_mV);
            off_r2r <= $signed(ref_mV) - $signed(r2r_mV);
        end
    end

    // --- 3) Apply offsets with simple clamping to 0..9999 (or 0..3300) ---

    logic signed [16:0] pwm_tmp, r2r_tmp; // one extra bit for overflow

    always_comb begin
        pwm_tmp = $signed({1'b0, pwm_mV}) + off_pwm;
        r2r_tmp = $signed({1'b0, r2r_mV}) + off_r2r;

        // clamp to 0..9999
        if (pwm_tmp < 0)
            pwm_mV_corr = 16'd0;
        else if (pwm_tmp > 9999)
            pwm_mV_corr = 16'd9999;
        else
            pwm_mV_corr = pwm_tmp[15:0];

        if (r2r_tmp < 0)
            r2r_mV_corr = 16'd0;
        else if (r2r_tmp > 9999)
            r2r_mV_corr = 16'd9999;
        else
            r2r_mV_corr = r2r_tmp[15:0];
    end

endmodule
