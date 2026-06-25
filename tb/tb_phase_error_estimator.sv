`timescale 1ps/1ps

module tb_phase_error_estimator;

    localparam int TDC_WIDTH     = 8;
    localparam int FRAC_WIDTH    = 16;
    localparam int PHF_INT_WIDTH = 3;
    localparam int SKIP_WIDTH    = 2;
    localparam int PHASE_WIDTH   = PHF_INT_WIDTH + FRAC_WIDTH;

    real t_res_ps    = 25.0;
    real t_period_ps = 416.7;

    logic clk;
    logic rst_n;

    logic tdc_valid;
    logic [TDC_WIDTH-1:0] tdc_code;
    logic [TDC_WIDTH-1:0] period_code;
    logic [PHF_INT_WIDTH-1:0] phf_int;
    logic signed [SKIP_WIDTH-1:0] tdc_skip;

    logic phase_error_valid;
    logic [FRAC_WIDTH-1:0] phf_frac;
    logic [FRAC_WIDTH:0] tvperinv;
    logic signed [PHF_INT_WIDTH+FRAC_WIDTH-1:0] phase_error;

    phase_error_estimator #(
        .TDC_WIDTH(TDC_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .PHF_INT_WIDTH(PHF_INT_WIDTH),
        .SKIP_WIDTH(SKIP_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .tdc_valid(tdc_valid),
        .tdc_code(tdc_code),
        .period_code(period_code),
        .phf_int(phf_int),
        .tdc_skip(tdc_skip),
        .phase_error_valid(phase_error_valid),
        .phf_frac(phf_frac),
        .tvperinv(tvperinv),
        .phase_error(phase_error)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic int tdc_model(input real delta_t_ps);
        begin
            tdc_model = int'(delta_t_ps / t_res_ps);
        end
    endfunction

    task automatic apply_phase_error_test(
        input real delta_ps,
        input int phf_i_val,
        input int skip_val
    );
        int tdc_val;
        int period_val;
        int tvperinv_val;
        int expected_frac_int;
        int expected_phase_error;
        real phase_error_norm;
        real phase_error_ideal;

        begin
            tdc_val          = tdc_model(delta_ps);
            period_val       = int'(t_period_ps / t_res_ps);
            tvperinv_val     = (1 << FRAC_WIDTH) / period_val;
            expected_frac_int = tdc_val * tvperinv_val;

            expected_phase_error = (phf_i_val << FRAC_WIDTH)
                                 + expected_frac_int[FRAC_WIDTH-1:0]
                                 + (skip_val << FRAC_WIDTH);

            phase_error_ideal = real'(phf_i_val + skip_val) + (delta_ps / t_period_ps);

            @(negedge clk);
            tdc_code    = tdc_val[TDC_WIDTH-1:0];
            period_code = period_val[TDC_WIDTH-1:0];
            phf_int     = phf_i_val[PHF_INT_WIDTH-1:0];
            tdc_skip    = skip_val[SKIP_WIDTH-1:0];
            tdc_valid   = 1'b1;

            @(posedge clk);
            #1;

            if (phase_error_valid !== 1'b1) begin
                $display("ERROR: phase_error_valid = 0");
                $fatal;
            end

            if (phase_error !== expected_phase_error) begin
                $display("ERROR: delta=%0f ps, PHF_I=%0d, skip=%0d", delta_ps, phf_i_val, skip_val);
                $display(" expected phase_error=%0d, got=%0d", expected_phase_error, phase_error);
                $fatal;
            end

            phase_error_norm = real'(phase_error) / (2.0 ** FRAC_WIDTH);

            $display(
                "OK: delta=%0.3f ps, tdc_code=%0d, period_code=%0d, PHF_I=%0d, skip=%0d, PHF_F=%0d, phase_error=%0d, norm=%f, ideal=%f",
                delta_ps,
                tdc_val,
                period_val,
                phf_i_val,
                skip_val,
                phf_frac,
                phase_error,
                phase_error_norm,
                phase_error_ideal
            );

            @(negedge clk);
            tdc_valid = 1'b0;
            tdc_code = '0;
            period_code = '0;
            phf_int = '0;
            tdc_skip = '0;
        end
    endtask

    initial begin
        $dumpfile("results/phase_error_estimator.vcd");
        $dumpvars(0, tb_phase_error_estimator);

        rst_n       = 1'b0;
        tdc_valid   = 1'b0;
        tdc_code    = '0;
        period_code = '0;
        phf_int     = '0;
        tdc_skip    = '0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        $display("\nFractional phase only, no skip\n");
        apply_phase_error_test(0.0,   0, 0);
        apply_phase_error_test(100.0, 0, 0);
        apply_phase_error_test(200.0, 0, 0);
        apply_phase_error_test(300.0, 0, 0);

        $display("\nFull phase error with integer phase part\n");
        apply_phase_error_test(0.0,   1, 0);
        apply_phase_error_test(100.0, 1, 0);
        apply_phase_error_test(200.0, 1, 0);
        apply_phase_error_test(300.0, 1, 0);

        $display("\nEdge-skip correction examples\n");
        apply_phase_error_test(100.0, 1,  1);
        apply_phase_error_test(100.0, 1, -1);

        $display("All tests completed.");
        $finish;
    end

endmodule

