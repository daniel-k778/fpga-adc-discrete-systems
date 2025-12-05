//==============================================================================
// lab7_top.sv
//
// Function:
//   Top-level integration for Lab 7: Discrete ADC Systems on Basys-3 FPGA.
//   This design implements:
//     • Built-in XADC sampling (reference digital ADC path)
//     • Discrete PWM-based ramp-compare ADC (external comparator path)
//     • Discrete R-2R-based ramp-compare ADC (external comparator path)
//     • On-board 4-digit 7-segment display output (hex or decimal)
//     • Debug LEDs for comparator monitoring
//
// Operation Summary:
//
//   The mode_select switch chooses one of three ADC subsystems:
//       2'b00 → XADC mode
//       2'b01 → PWM ramp-compare ADC mode
//       2'b10 → R2R ramp-compare ADC mode
//
//   The bin_bcd_select switch chooses display formatting:
//       2'b00 → Averaged HEX value
//       2'b01 → Scaled decimal value (millivolts)
//       2'b10 → Raw HEX value (discrete ADC: 0-FF)
//       2'b11 → Raw HEX value (discrete ADC: 0-FF)
//
//   The selected ADC subsystem drives the internal display multiplexer,
//   which provides digit values for the 7-segment driver.
//
// External Hardware Connections:
//
//   • pwm_out → RC Low-Pass Filter → Comparator → comp_pwm_in
//   • R2R_out[7:0] → R-2R Ladder → Comparator → comp_r2r_in
//   • vauxp15/vauxn15 → XADC analog input pins (Lab 5 reference path)
//
// Inputs:
//   clk            : 100 MHz FPGA clock
//   reset          : Active-high synchronous reset
//   bin_bcd_select : Display format selector (switches)
//   mode_select    : Selects active ADC subsystem (switches)
//   vauxp15/vauxn15: XADC analog input pair
//   comp_pwm_in    : Comparator output for PWM ramp ADC
//   comp_r2r_in    : Comparator output for R2R ramp ADC
//
// Outputs:
//   pwm_out        : PWM DAC signal to RC filter
//   R2R_out[7:0]   : 8-bit DAC bus to R-2R ladder
//   7-seg display  : CA..CG, DP, AN1..AN4
//   led[1:0]       : Debug (shows comparator states)
//
//==============================================================================

module lab7_top (
    input  logic        clk,
    input  logic        reset,
    input  logic [1:0]  bin_bcd_select, // switches[3:2]
    input  logic [1:0]  mode_select,    // switches[2:0]
    input  logic        sar_select,    // switches[15]

    // XADC analog pins
    input  logic        vauxp15,
    input  logic        vauxn15,

    // Comparator outputs -> FPGA
    input  logic        comp_pwm_in,
    input  logic        comp_r2r_in,

    // DAC outputs -> circuit
    output logic        pwm_out,     // pwm_out -> RC Filter -> Comparator
    output logic [7:0]  R2R_out,     // R2R_out -> R2R Ladder Network -> Comparator

    // 7-seg display
    output logic        CA, CB, CC, CD, CE, CF, CG, DP,
    output logic        AN1, AN2, AN3, AN4,
    output logic [15:0] led,
    input  logic        cal_btn
);

    // Assign comparator outputs to LEDS for easier debugging
    assign led[0] = comp_pwm_in;
    assign led[1] = comp_r2r_in;
    
    // ========== XADC ==========
    logic [15:0] adc_raw16, adc_raw12_hex, adc_avg16, adc_scaled_mV;
    logic        adc_sample_pulse, adc_busy, adc_eos;

    adc_subsystem u_xadc (
        .clk          (clk),
        .reset        (reset),
        .vauxp15      (vauxp15),
        .vauxn15      (vauxn15),
        .raw16        (adc_raw16),
        .raw12_hex    (adc_raw12_hex),
        .avg16        (adc_avg16),
        .scaled_mV    (adc_scaled_mV),
        .sample_pulse (adc_sample_pulse),
        .busy         (adc_busy),
        .eos          (adc_eos)
    );
    
    logic pwm_enable;
    logic r2r_enable;

    // ========== PWM RAMP COMPARE ADC ==========
    logic [7:0]  pwm_raw8, pwm_avg8;
    logic [15:0] pwm_scaled;      // 0..9999
    logic [15:0] pwm_mV;          // 0..3300 mV (scaled from avg8)
    logic        pwm_ready;

    
    discrete_pwm_adc u_pwmadc (
        .clk         (clk),
        .reset       (reset),
        .enable      (pwm_enable),
        .algo_sar    (sar_select),
        .comp_in     (comp_pwm_in),
        .pwm_out     (pwm_out),
        .raw8        (pwm_raw8),
        .avg8        (pwm_avg8),
        .scaled_9999 (pwm_scaled),
        .ready_pulse (pwm_ready)
    );

    // ========== R2R RAMP COMPARE ADC ==========
    logic [7:0]  r2r_raw8, r2r_avg8;
    logic [15:0] r2r_scaled;      // 0..9999
    logic [15:0] r2r_mV;          // 0..3300 mV (scaled from avg8)
    logic        r2r_ready;

    discrete_r2r_adc u_r2radc (
        .clk         (clk),
        .reset       (reset),
        .enable      (r2r_enable),
        .algo_sar    (sar_select),
        .comp_in     (comp_r2r_in),
        .R2R_out     (R2R_out),
        .raw8        (r2r_raw8),
        .avg8        (r2r_avg8),
        .scaled_9999 (r2r_scaled),
        .ready_pulse (r2r_ready)
    );
    
    
    // ========== Auto Calibration ==========
    logic [15:0] pwm_mV_cal;
    logic [15:0] r2r_mV_cal;

    adc_auto_calib u_cal (
        .clk        (clk),
        .reset      (reset),
        .cal_btn    (cal_btn),

        .ref_mV     (adc_scaled_mV), // XADC ref (already scaled to mV)
        .pwm_mV     (pwm_mV),
        .r2r_mV     (r2r_mV),

        .pwm_mV_corr(pwm_mV_cal),
        .r2r_mV_corr(r2r_mV_cal)
    );

    // ========== SCALING TO mV FOR RAMP COMPARE ADCs ==========
    
    code8_to_mV u_pwm_mv (
        .clk    (clk),
        .reset  (reset),
        .en     (pwm_ready),
        .code_in(pwm_avg8),
        .mV_out (pwm_mV)
    );
    
    code8_to_mV u_r2r_mv (
        .clk    (clk),
        .reset  (reset),
        .en     (r2r_ready),
        .code_in(r2r_avg8),
        .mV_out (r2r_mV)
    );


    // ========== DISPLAY MUX ==========
    
    logic [3:0] dig0, dig1, dig2, dig3;
    logic [3:0] dp_vec;
    
    adc_display_mux u_disp_mux (
        .clk            (clk),
        .reset          (reset),
        .mode_select    (mode_select),
        .bin_bcd_select (bin_bcd_select),
    
        // XADC
        .adc_raw12_hex  (adc_raw12_hex),
        .adc_avg16      (adc_avg16),
        .adc_scaled_mV  (adc_scaled_mV),
    
        // PWM
        .pwm_raw8       (pwm_raw8),
        .pwm_avg8       (pwm_avg8),
        .pwm_mV         (pwm_mV_cal),
    
        // R2R
        .r2r_raw8       (r2r_raw8),
        .r2r_avg8       (r2r_avg8),
        .r2r_mV         (r2r_mV_cal),
    
        // Outputs to 7-seg subsystem
        .dig0           (dig0),
        .dig1           (dig1),
        .dig2           (dig2),
        .dig3           (dig3),
        .dp_vec         (dp_vec),
        .pwm_enable(pwm_enable),
        .r2r_enable(r2r_enable)
    );

    seven_segment_display_subsystem u7 (
        .clk           (clk),
        .reset         (reset),
        .sec_dig1      (dig0),
        .sec_dig2      (dig1),
        .min_dig1      (dig2),
        .min_dig2      (dig3),
        .decimal_point (dp_vec),
        .CA(CA), .CB(CB), .CC(CC), .CD(CD),
        .CE(CE), .CF(CF), .CG(CG), .DP(DP),
        .AN1(AN1), .AN2(AN2), .AN3(AN3), .AN4(AN4)
    );

endmodule
