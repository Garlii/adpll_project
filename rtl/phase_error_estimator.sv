module phase_error_estimator #(
    parameter int TDC_WIDTH  = 8,
    parameter int FRAC_WIDTH = 16,
    parameter int PHF_INT_WIDTH = 3,
    parameter int SKIP_WIDTH    = 2
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     tdc_valid,
    input  logic [PHF_INT_WIDTH]     phf_int,
    input  logic [TDC_WIDTH-1:0]     tdc_code,
    input  logic [TDC_WIDTH-1:0]     period_code,
    input  logic signed [SKIP_WIDTH-1:0] tdc_skip,

    output logic                     phase_error_valid,
    output logic [FRAC_WIDTH-1:0]    phf_frac,
    output logic [FRAC_WIDTH:0]	     tvperinv,
    output logic signed [PHF_INT_WIDTH+FRAC_WIDTH-1:0]   phase_error
);

localparam int PHASE_WIDTH = PHF_INT_WIDTH + FRAC_WIDTH + 1;

    logic [FRAC_WIDTH:0] tvperinv_calc;
    logic [TDC_WIDTH+FRAC_WIDTH:0] phf_mult;
    logic [FRAC_WIDTH-1:0] phf_frac_calc;

    logic signed [PHASE_WIDTH-1:0] phase_no_skip;
    logic signed [PHASE_WIDTH-1:0] skip_correction;
    logic signed [PHASE_WIDTH-1:0] phase_error_calc;

    always @* begin
        if (period_code != 0)
            tvperinv_calc = (1 << FRAC_WIDTH) / period_code;
        else
            tvperinv_calc = '0;

        phf_mult      = tdc_code * tvperinv_calc;
        phf_frac_calc = phf_mult[FRAC_WIDTH-1:0];

        // Full phase error = integer part + fractional part + optional edge-skip correction.
        phase_no_skip    = $signed({1'b0, phf_int, phf_frac_calc});
        skip_correction  = $signed(tdc_skip) <<< FRAC_WIDTH;
        phase_error_calc = phase_no_skip + skip_correction;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phf_frac          <= '0;
            phase_error       <= '0;
            tvperinv          <= '0;
            phase_error_valid <= 1'b0;
        end else begin
            if (tdc_valid && period_code != 0) begin
                tvperinv          <= tvperinv_calc;
                phf_frac          <= phf_frac_calc;
                phase_error       <= phase_error_calc;
                phase_error_valid <= 1'b1;
            end else begin
                phase_error_valid <= 1'b0;
            end
        end
    end

endmodule
    
