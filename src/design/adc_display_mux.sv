// Select which ADC value to show and in which format,
// then drive 4 hex/decimal digits + decimal-point vector
module adc_display_mux (
    input  logic        clk,
    input  logic        reset,
    input  logic [1:0]  mode_select,    // 00=XADC, 01=PWM, 10=R2R
    input  logic [1:0]  bin_bcd_select, // 00=avg HEX, 01=decimal, 10/11=raw HEX

    // XADC inputs
    input  logic [15:0] adc_raw12_hex,
    input  logic [15:0] adc_avg16,
    input  logic [15:0] adc_scaled_mV,

    // PWM discrete ADC inputs
    input  logic [7:0]  pwm_raw8,
    input  logic [7:0]  pwm_avg8,
    input  logic [15:0] pwm_mV,

    // R2R discrete ADC inputs
    input  logic [7:0]  r2r_raw8,
    input  logic [7:0]  r2r_avg8,
    input  logic [15:0] r2r_mV,

    // Outputs to seven_segment_display_subsystem
    output logic [3:0]  dig0,
    output logic [3:0]  dig1,
    output logic [3:0]  dig2,
    output logic [3:0]  dig3,
    output logic [3:0]  dp_vec,
    
    output logic pwm_enable,
    output logic r2r_enable
);
    // Internal selection wires
    logic [15:0] sel_raw_hex16, sel_avg_hex16, sel_scaled_dec;
    logic [15:0] bcd_value, bcd_digits;

    // -------- Select which ADC to pull data from --------
    always_comb begin
        sel_raw_hex16  = '0;
        sel_avg_hex16  = '0;
        sel_scaled_dec = '0;
        
        pwm_enable = 1'b0;
        r2r_enable = 1'b0;
        
        unique case (mode_select)
            2'b00: begin // XADC
                sel_raw_hex16  = adc_raw12_hex;
                sel_avg_hex16  = adc_avg16;
                sel_scaled_dec = adc_scaled_mV;
            end
            2'b01: begin // PWM ADC
                sel_raw_hex16  = {8'h00, pwm_raw8};
                sel_avg_hex16  = {8'h00, pwm_avg8};
                sel_scaled_dec = pwm_mV;
                pwm_enable = 1'b1; // PWM mode
            end
            2'b10: begin // R2R ADC
                sel_raw_hex16  = {8'h00, r2r_raw8};
                sel_avg_hex16  = {8'h00, r2r_avg8};
                sel_scaled_dec = r2r_mV;
                r2r_enable = 1'b1; // R-2R mode
            end
            default: ;
        endcase
    end

    // Assign the BCD_VALUE to the corrosponding ADC we selected from
    assign bcd_value = sel_scaled_dec;

    // Binary-to-BCD conversion
    bin_to_bcd u_b2b (
        .bin_in  (bcd_value),
        .bcd_out (bcd_digits),
        .clk     (clk),
        .reset   (reset)
    );

    // -------- Display selection --------
    // 00: averaged HEX, 01: scaled decimal, 10/11: raw HEX
    always_comb begin
        dp_vec = 4'b0000;

        unique case (bin_bcd_select)
            2'b00: begin // AVERAGED HEX (mV)
                dig3  = sel_avg_hex16[15:12];
                dig2  = sel_avg_hex16[11:8];
                dig1  = sel_avg_hex16[7:4];
                dig0  = sel_avg_hex16[3:0];
            end
            2'b01: begin // DECIMAL (mV)
                dig3  = bcd_digits[15:12];
                dig2  = bcd_digits[11:8];
                dig1  = bcd_digits[7:4];
                dig0  = bcd_digits[3:0];
                dp_vec = 4'b0000;
            end
            default: begin // RAW HEX
                dig3  = sel_raw_hex16[15:12];
                dig2  = sel_raw_hex16[11:8];
                dig1  = sel_raw_hex16[7:4];
                dig0  = sel_raw_hex16[3:0];
            end
        endcase
    end

endmodule
