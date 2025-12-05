//==============================================================================
// sar_controller.sv  (single-driver FSM version)
//
// Generic successive-approximation controller for an N-bit ADC.
// Drives a DAC code bus and uses a single comparator output.
//==============================================================================

module sar_controller #(
    parameter int WIDTH          = 8,
    parameter int SETTLE_CYCLES  = 5000  // wait cycles between bit decisions
)(
    input  logic             clk,
    input  logic             reset,
    input  logic             enable,     // start / keep running conversions
    input  logic             comp_in,    // async comparator output (1 when Vin > Vdac)

    output logic [WIDTH-1:0] dac_code,   // drives DAC
    output logic             ready_pulse // 1-cycle strobe when new code done
);

    //========================
    // 1) Synchronize comp_in
    //========================
    logic comp_meta, comp_sync;

    always_ff @(posedge clk) begin
        if (reset) begin
            comp_meta <= 1'b0;
            comp_sync <= 1'b0;
        end else begin
            comp_meta <= comp_in;
            comp_sync <= comp_meta;
        end
    end

    //========================
    // 2) FSM declarations
    //========================
    typedef enum logic [2:0] {
        S_IDLE,
        S_START,
        S_SETBIT,
        S_WAIT,
        S_COMPARE,
        S_DONE
    } state_t;

    state_t state, next_state;

    // bit index (MSB down to 0)
    localparam int BIT_INDEX_WIDTH = (WIDTH <= 1) ? 1 : $clog2(WIDTH);
    logic [BIT_INDEX_WIDTH-1:0] bit_index, bit_index_next;

    // settle counter
    localparam int SETTLE_WIDTH = (SETTLE_CYCLES <= 1) ? 1 : $clog2(SETTLE_CYCLES);
    logic [SETTLE_WIDTH-1:0] settle_cnt, settle_cnt_next;
    logic                    settle_done;

    assign settle_done = (settle_cnt == SETTLE_CYCLES-1);

    // "next" versions of outputs
    logic [WIDTH-1:0] dac_code_next;
    logic             ready_pulse_next;

    //========================
    // 3) Sequential block
    //    (single driver for all regs)
//========================
    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;
            dac_code    <= '0;
            bit_index   <= '0;
            settle_cnt  <= '0;
            ready_pulse <= 1'b0;
        end else begin
            state       <= next_state;
            dac_code    <= dac_code_next;
            bit_index   <= bit_index_next;
            settle_cnt  <= settle_cnt_next;
            ready_pulse <= ready_pulse_next;
        end
    end

    //========================
    // 4) Combinational next-state / next-data logic
    //========================
    always_comb begin
        // defaults: hold values
        next_state       = state;
        dac_code_next    = dac_code;
        bit_index_next   = bit_index;
        settle_cnt_next  = settle_cnt;
        ready_pulse_next = 1'b0;   // default low, only 1-cycle in S_DONE

        case (state)
            //----------------------------------------------------------
            S_IDLE: begin
                // wait for enable to start a new conversion
                settle_cnt_next = '0;
                if (enable) begin
                    next_state     = S_START;
                end
            end

            //----------------------------------------------------------
            S_START: begin
                // initialize code and bit index
                dac_code_next   = '0;
                bit_index_next  = WIDTH-1;
                settle_cnt_next = '0;
                next_state      = S_SETBIT;
            end

            //----------------------------------------------------------
            S_SETBIT: begin
                // set current bit = 1 (trial)
                dac_code_next              = dac_code;
                dac_code_next[bit_index]   = 1'b1;
                settle_cnt_next            = '0;
                next_state                 = S_WAIT;
            end

            //----------------------------------------------------------
            S_WAIT: begin
                // wait for DAC + comparator to settle
                if (!settle_done) begin
                    settle_cnt_next = settle_cnt + 1'b1;
                    next_state      = S_WAIT;
                end else begin
                    next_state      = S_COMPARE;
                end
            end

            //----------------------------------------------------------
            S_COMPARE: begin
                // decide whether to keep bit = 1 or clear to 0
                dac_code_next = dac_code;
                if (!comp_sync) begin
                    // Vin < Vdac -> code too large -> clear bit
                    dac_code_next[bit_index] = 1'b0;
                end
                // else Vin > Vdac -> keep bit = 1

                // move to next bit or finish
                if (bit_index != '0) begin
                    bit_index_next = bit_index - 1'b1;
                    next_state     = S_SETBIT;
                end else begin // bit index 0 and comparator is 1 go to end state
                    next_state     = S_DONE;
                end
            end

            //----------------------------------------------------------
            S_DONE: begin
                // conversion complete; assert ready for one cycle
                ready_pulse_next = 1'b1;

                // either immediately start next conversion or idle
                if (enable)
                    next_state = S_START;
                else
                    next_state = S_IDLE;
            end

            //----------------------------------------------------------
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

endmodule
