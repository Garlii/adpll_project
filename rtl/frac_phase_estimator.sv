module frac_phase_estimator #(
    parameter TDC_WIDTH  = 8,
    parameter FRAC_WIDTH = 16
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     meas_valid,
    input  logic [TDC_WIDTH-1:0]     tdc_code,
    input  logic [TDC_WIDTH-1:0]     period_code,

    output logic                     phf_valid,
    output logic [FRAC_WIDTH-1:0]    phf_frac
);

    logic [TDC_WIDTH+FRAC_WIDTH-1:0] numerator;

    always_comb begin
        numerator = {tdc_code, {FRAC_WIDTH{1'b0}}};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phf_frac  <= '0;
            phf_valid <= 1'b0;
        end else begin
            if (meas_valid && period_code != 0) begin
                phf_frac  <= numerator / period_code;
                phf_valid <= 1'b1;
            end else begin
                phf_valid <= 1'b0;
            end
        end
    end

endmodule
