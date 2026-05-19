`timescale 1ps/1ps

module tb_frac_phase_estimator;

    localparam int TDC_WIDTH  = 8;
    localparam int FRAC_WIDTH = 16;
    
    real t_res_ps    = 25.0; //rozdzielczość TDC
    real t_period_ps = 416.7; //okres DCO dla ok 2.4 GHz

    real phf_est_norm;
    real phf_ideal;

    integer csv_file;
    string csv_filename;

    logic clk;
    logic rst_n;
    logic fref_test;
    logic ckv_test;

    logic meas_valid;
    logic [TDC_WIDTH-1:0] tdc_code;
    logic [TDC_WIDTH-1:0] period_code;

    logic phf_valid;
    logic [FRAC_WIDTH-1:0] phf_frac;

    logic phf_int;
    logic [FRAC_WIDTH:0] phase_error;

    logic [FRAC_WIDTH:0] tvperinv;

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
	.tvperinv(tvperinv),
	.phf_int(phf_int),
	.phase_error(phase_error),
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
    int expected_frac;
    int tvperinv_val;
    begin
        tvperinv_val = (1 << FRAC_WIDTH) / period_val;
	expected_frac = tdc_val * tvperinv_val;

        // Ustawiamy dane przed aktywnym zboczem zegara
        @(negedge clk);
        tdc_code    = tdc_val[TDC_WIDTH-1:0];
        period_code = period_val[TDC_WIDTH-1:0];
	phf_int = 1'b0;
        meas_valid  = 1'b1;

        // Na tym zboczu DUT powinien pobrać dane i policzyć wynik
        @(posedge clk);
        #1;

        if (phf_valid !== 1'b1) begin
            $display("ERROR: phf_valid = 0 dla tdc_code=%0d, period_code=%0d",
                     tdc_val, period_val);
            $fatal;
        end

        if (phf_frac !== expected_frac) begin
            $display("ERROR: zly wynik dla tdc_code=%0d, period_code=%0d",
                     tdc_val, period_val);
            $display("       oczekiwano: %0d, otrzymano: %0d",
                     expected_frac, phf_frac);
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
    logic [FRAC_WIDTH-1:0] expected_frac;
    int tvperinv_val;

    begin
        tdc_val   = tdc_model(delta_t_ps);
        period_val = int'(t_period_ps / t_res_ps);

        tvperinv_val = (1 << FRAC_WIDTH) / period_val;
	expected_frac = tdc_val * tvperinv_val;

        @(negedge clk);
        tdc_code    = tdc_val[TDC_WIDTH-1:0];
        period_code = period_val[TDC_WIDTH-1:0];
	phf_int = 1'b0;
        meas_valid  = 1'b1;

        @(posedge clk);
        #1;

        if (phf_frac !== expected_frac) begin
            $display("ERROR Δt=%0f ps", delta_t_ps);
            $display(" expected_frac=%0d got=%0d", expected_frac, phf_frac);
            $fatal;
        end else begin
            $display("OK Δt=%0f ps → phf=%0d", delta_t_ps, phf_frac);
        end

        @(negedge clk);
        meas_valid = 0;
    end
endtask


task automatic apply_clock_pair_test(input real delta_ps);
    int tdc_val;
    int period_val;
    real phf_ideal_local;
    real phf_est_local;

    begin
        fref_test = 1'b0;
        ckv_test  = 1'b0;

        // Generacja pary zboczy CKV i FREF.
        // CKV pojawia się jako początek okresu,
        // FREF jest opóźniony o delta_ps.
        #(10);
        ckv_test = 1'b1;
        #(1);
        ckv_test = 1'b0;

        #(delta_ps);
        fref_test = 1'b1;
        #(1);
        fref_test = 1'b0;

        // Funkcjonalny model TDC dostaje opóźnienie wynikające
        // z zadanej relacji czasowej między CKV i FREF.
        tdc_val    = tdc_model(delta_ps);
        period_val = int'(t_period_ps / t_res_ps);

        phf_ideal_local = delta_ps / t_period_ps;

        @(negedge clk);
        tdc_code    = tdc_val[TDC_WIDTH-1:0];
        period_code = period_val[TDC_WIDTH-1:0];
	phf_int = 1'b0;
        meas_valid  = 1'b1;

        @(posedge clk);
        #1;

        phf_est_local = real'(phf_frac) / (2.0 ** FRAC_WIDTH);

        $display(
            "CLOCK_PAIR delta=%0.3f ps, tdc_code=%0d, period_code=%0d, phf=%0d, est=%f, ideal=%f, error=%f",
            delta_ps,
            tdc_val,
            period_val,
            phf_frac,
            phf_est_local,
            phf_ideal_local,
            phf_est_local - phf_ideal_local
        );

        @(negedge clk);
        meas_valid = 1'b0;
    end
endtask


task automatic run_resolution_sweep(
    input real res_ps,
    input string filename
);
    int tdc_val;
    int period_val;
    real delta;

    begin
        t_res_ps = res_ps;

        csv_file = $fopen(filename, "w");

        $fwrite(csv_file,
            "delta_t_ps,tdc_code,phf_est_norm,phf_ideal\n"
        );

        // Sweep podstawowy
        for (int i = 0; i <= 400; i += 5) begin
            delta = i;

            tdc_val    = tdc_model(delta);
            period_val = int'(t_period_ps / t_res_ps);

            phf_ideal = delta / t_period_ps;

            @(negedge clk);
            tdc_code    = tdc_val[TDC_WIDTH-1:0];
            period_code = period_val[TDC_WIDTH-1:0];
	    phf_int = 1'b0;
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

        // Testy brzegowe - tylko wypisanie na terminal,
// bez zapisu do CSV, żeby nie zaburzać statystyk RMS.
for (int j = 0; j < 4; j++) begin
    case (j)
        0: delta = 1.0;
        1: delta = 2.0;
        2: delta = t_period_ps - 2.0;
        3: delta = t_period_ps - 1.0;
    endcase

    tdc_val    = tdc_model(delta);
    period_val = int'(t_period_ps / t_res_ps);

    phf_ideal = delta / t_period_ps;

    @(negedge clk);
    tdc_code    = tdc_val[TDC_WIDTH-1:0];
    period_code = period_val[TDC_WIDTH-1:0];
    phf_int = 1'b0;
    meas_valid  = 1'b1;

    @(posedge clk);
    #1;

    phf_est_norm = real'(phf_frac) / (2.0 ** FRAC_WIDTH);

    $display(
        "BOUNDARY res=%0.1f ps, delta=%0.3f ps -> tdc_code=%0d, period_code=%0d, phf=%0d, est=%f, ideal=%f, error=%f",
        t_res_ps,
        delta,
        tdc_val,
        period_val,
        phf_frac,
        phf_est_norm,
        phf_ideal,
        phf_est_norm - phf_ideal
    );

    @(negedge clk);
    meas_valid = 1'b0;
end

        $fclose(csv_file);

        $display("CSV zapisany: %s", filename);
    end
endtask

task automatic apply_phase_error_test(
    input real delta_ps,
    input logic phf_i_val
);
    int tdc_val;
    int period_val;
    logic [FRAC_WIDTH-1:0] expected_frac;
    int expected_phase_error;
    int tvperinv_val;
    real phase_error_norm;
    real phase_error_ideal;

    begin
        tdc_val    = tdc_model(delta_ps);
        period_val = int'(t_period_ps / t_res_ps);

        tvperinv_val = (1 << FRAC_WIDTH) / period_val;
	expected_frac = tdc_val * tvperinv_val;

        expected_phase_error = (phf_i_val << FRAC_WIDTH)
                             + expected_frac;

        phase_error_ideal = real'(phf_i_val) + (delta_ps / t_period_ps);

        @(negedge clk);
        phf_int     = phf_i_val;
        tdc_code    = tdc_val[TDC_WIDTH-1:0];
        period_code = period_val[TDC_WIDTH-1:0];
        meas_valid  = 1'b1;

        @(posedge clk);
        #1;

        phase_error_norm = real'(phase_error) / (2.0 ** FRAC_WIDTH);

        if (phf_frac !== expected_frac) begin
            $display("ERROR PHASE_ERROR: delta=%0f ps, PHF_I=%0d",
                     delta_ps, phf_i_val);
            $display(" expected_frac=%0d got=%0d",
                     expected_phase_error, phase_error);
            $fatal;
        end else begin
            $display(
                "OK PHASE_ERROR: PHF_I=%0d, delta=%0f ps -> phase_error=%0d, norm=%f, ideal=%f",
                phf_i_val,
                delta_ps,
                phase_error,
                phase_error_norm,
                phase_error_ideal
            );
        end

        @(negedge clk);
        meas_valid = 1'b0;
        phf_int = 1'b0;
    end
endtask


    initial begin

        $dumpfile("results/frac_phase_estimator.vcd");
        $dumpvars(0, tb_frac_phase_estimator);

        rst_n       = 1'b0;
        meas_valid  = 1'b0;
        tdc_code    = '0;
        period_code = '0;
	phf_int = 1'b0;

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


	apply_time_test(1.0);
	apply_time_test(2.0);

	apply_time_test(t_period_ps - 2.0);
	apply_time_test(t_period_ps - 1.0);

	$display("\nClock pair functional tests\n");

	t_res_ps = 25.0;

	apply_clock_pair_test(0.0);
	apply_clock_pair_test(50.0);
	apply_clock_pair_test(100.0);
	apply_clock_pair_test(200.0);
	apply_clock_pair_test(300.0);
	apply_clock_pair_test(400.0);


$display("\nFull phase error tests\n");

// zakres 0...1
apply_phase_error_test(0.0,   1'b0);
apply_phase_error_test(100.0, 1'b0);
apply_phase_error_test(200.0, 1'b0);
apply_phase_error_test(300.0, 1'b0);

// zakres 1...2
apply_phase_error_test(0.0,   1'b1);
apply_phase_error_test(100.0, 1'b1);
apply_phase_error_test(200.0, 1'b1);
apply_phase_error_test(300.0, 1'b1);


run_resolution_sweep(25.0, "results/phf_sweep_25ps.csv");
run_resolution_sweep(30.0, "results/phf_sweep_30ps.csv");
run_resolution_sweep(35.0, "results/phf_sweep_35ps.csv");
run_resolution_sweep(40.0, "results/phf_sweep_40ps.csv");
    

        $display("Wszystkie testy zakonczone poprawnie.");
        $finish;
    end

endmodule
