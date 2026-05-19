module frac_phase_estimator #(
    parameter TDC_WIDTH  = 8,
    parameter FRAC_WIDTH = 16
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     meas_valid,
    input  logic                     phf_int,
    input  logic [TDC_WIDTH-1:0]     tdc_code,
    input  logic [TDC_WIDTH-1:0]     period_code,

    output logic                     phf_valid,
    output logic [FRAC_WIDTH-1:0]    phf_frac,
    output logic [FRAC_WIDTH:0]	     tvperinv,
    output logic [FRAC_WIDTH:0]      phase_error
);

logic [FRAC_WIDTH:0] tvperinv_calc;
logic [TDC_WIDTH+FRAC_WIDTH:0] phf_mult;
logic [FRAC_WIDTH-1:0] phf_frac_calc;

always_comb begin
    if (period_code != 0)
        tvperinv_calc = (1 << FRAC_WIDTH) / period_code;
    else
        tvperinv_calc = '0;

    phf_mult = tdc_code * tvperinv_calc;
    phf_frac_calc = phf_mult[FRAC_WIDTH-1:0];
end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
   		 phf_frac    <= '0;
    		 phase_error <= '0;
    		 tvperinv    <= '0;
    		 phf_valid   <= 1'b0;
end else begin
    if (meas_valid && period_code != 0) begin
        tvperinv    <= tvperinv_calc;
        phf_frac    <= phf_frac_calc;
        phase_error <= {phf_int, phf_frac_calc};
        phf_valid   <= 1'b1;
    end else begin
        phf_valid <= 1'b0;
		end
	end
end

endmodule
