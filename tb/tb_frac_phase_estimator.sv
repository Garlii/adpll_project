`timescale 1ns/1ps

module tb_frac_phase_estimator;

    localparam int TDC_WIDTH  = 8;
    localparam int FRAC_WIDTH = 16;
    
    real t_res_ps    = 25.0; //rozdzielczość TDC
    real t_period_ps = 416.7; //okres DCO dla ok 2.4 GHz

    real phf_est_norm;
    real phf_ideal;

    integer csv_file;

    logic clk;
    logic rst_n;

    logic meas_valid;
    logic [TDC_WIDTH-1:0] tdc_code;
    logic [TDC_WIDTH-1:0] period_code;

    logic phf_valid;
    logic [FRAC_WIDTH-1:0] phf_frac;

    frac_phase_estimator #(
        .TDC_WIDTH(TDC_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .meas_valid(meas_valid),
        .tdc_code(tdc_code),
        .period_code(period_code),
        .phf_valid(phf_valid),
        .phf_frac(phf_frac)
    );

    initial begin  

    clk = 1'b0;
        forever #5 clk = ~clk;   // okres zegara = 10 ns
    end

task automatic apply_test(
    input int tdc_val,
    input int period_val
);
    int expected;

    begin
        expected = (tdc_val << FRAC_WIDTH) / period_val;

        // Ustawiamy dane przed aktywnym zboczem zegara
        @(negedge clk);
        tdc_code    = tdc_val[TDC_WIDTH-1:0];
        period_code = period_val[TDC_WIDTH-1:0];
        meas_valid  = 1'b1;

        // Na tym zboczu DUT powinien pobrać dane i policzyć wynik
        @(posedge clk);
        #1;

        if (phf_valid !== 1'b1) begin
            $display("ERROR: phf_valid = 0 dla tdc_code=%0d, period_code=%0d",
                     tdc_val, period_val);
            $fatal;
        end

        if (phf_frac !== expected[FRAC_WIDTH-1:0]) begin
            $display("ERROR: zly wynik dla tdc_code=%0d, period_code=%0d",
                     tdc_val, period_val);
            $display("       oczekiwano: %0d, otrzymano: %0d",
                     expected, phf_frac);
            $fatal;
        end else begin
            $display("OK: tdc_code=%0d, period_code=%0d, phf_frac=%0d",
                     tdc_val, period_val, phf_frac);
        end

        @(negedge clk);
        meas_valid = 1'b0;
        tdc_code = '0;
        period_code = '0;
    end
endtask

function automatic int tdc_model(input real delta_t_ps);
    begin
        tdc_model = int'(delta_t_ps / t_res_ps);
    end
endfunction

task automatic apply_time_test(real delta_t_ps);
    int tdc_val;
    int period_val;
    int expected;

    begin
        tdc_val   = tdc_model(delta_t_ps);
        period_val = int'(t_period_ps / t_res_ps);

        expected = (tdc_val << FRAC_WIDTH) / period_val;

        @(negedge clk);
        tdc_code    = tdc_val[TDC_WIDTH-1:0];
        period_code = period_val[TDC_WIDTH-1:0];
        meas_valid  = 1'b1;

        @(posedge clk);
        #1;

        if (phf_frac !== expected[FRAC_WIDTH-1:0]) begin
            $display("ERROR Δt=%0f ps", delta_t_ps);
            $display(" expected=%0d got=%0d", expected, phf_frac);
            $fatal;
        end else begin
            $display("OK Δt=%0f ps → phf=%0d", delta_t_ps, phf_frac);
        end

        @(negedge clk);
        meas_valid = 0;
    end
endtask



    initial begin

	 csv_file = $fopen("results/phf_sweep.csv", "w");

	    $fwrite(csv_file,
	"delta_t_ps,tdc_code,phf_est_norm,phf_ideal\n");

        $dumpfile("results/frac_phase_estimator.vcd");
        $dumpvars(0, tb_frac_phase_estimator);

        rst_n       = 1'b0;
        meas_valid  = 1'b0;
        tdc_code    = '0;
        period_code = '0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        apply_test(0, 16);    // 0.0 okresu
        apply_test(4, 16);    // 0.25 okresu
        apply_test(8, 16);    // 0.5 okresu
        apply_test(12, 16);   // 0.75 okresu
        apply_test(15, 16);   // prawie 1 okres

        apply_test(1, 17);
        apply_test(8, 17);
        apply_test(16, 17);

        apply_test(5, 20);
        apply_test(10, 20);
        apply_test(19, 20);
        
        apply_time_test(0.0);
	apply_time_test(50.0);
	apply_time_test(100.0);
	apply_time_test(200.0);
	apply_time_test(300.0);
	apply_time_test(400.0);

for (int i = 0; i <= 400; i += 5) begin
    real delta;
    int tdc_val;
    int period_val;

    delta = i;

    tdc_val    = tdc_model(delta);
    period_val = int'(t_period_ps / t_res_ps);

    phf_ideal = delta / t_period_ps;

    @(negedge clk);
    tdc_code    = tdc_val[TDC_WIDTH-1:0];
    period_code = period_val[TDC_WIDTH-1:0];
    meas_valid  = 1'b1;

    @(posedge clk);
    #1;

    phf_est_norm = real'(phf_frac) / (2.0 ** FRAC_WIDTH);

    $fwrite(csv_file,
        "%f,%0d,%f,%f\n",
        delta,
        tdc_val,
        phf_est_norm,
        phf_ideal
    );

    @(negedge clk);
    meas_valid = 1'b0;
end

$fclose(csv_file);

        $display("Wszystkie testy zakonczone poprawnie.");
        $finish;
    end

endmodule
