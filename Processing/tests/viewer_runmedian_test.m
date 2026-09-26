function tests = viewer_runmedian_test
% Seeded production renders of the L2: Candidates daily run median and the
% run-relative SNR filter: one circular-median point per day at the run
% midpoint, per-capture filtering that thins (not drops) a run, the
% contributor minimum, chain-cal before the median, unwrap over day medians,
% overflow provenance, aggregation after the collapse, SNR coloring, theta /
% theory / AboveFreezing-Nearest consumers, stage-specific empty messages and
% the side-panel Enable states.
% Run: matlab -batch "soop_setup_paths; addpath('tests'); runtests('viewer_runmedian_test')"
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.U = soop_viewer_util();
    tc.TestData.t0 = datetime(2026, 1, 1);
    f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    tc.TestData.dir = f.Folder;
end


% ------------------------------------------------------------------ harness

function V = seeded_viewer(tc)
% Real viewer state + layout (headless), mirroring viewer_ovf_filter_test.
    cfg = struct('freq_hz', 370e6, 'fs', 20e6, 'num_segs', 2, 'Ti', 0.9, ...
                 'peak_lag', -0.575, 'T_load_K', 290, ...
                 'out_dir', tc.TestData.dir, 'data_dir', tc.TestData.dir);
    V = SoopViewerState();
    V.cfg = cfg;
    V.M = BrundageSoOp_fun();
    V.npts = floor(cfg.fs * cfg.Ti);  V.n_want = V.npts * cfg.num_segs;
    V.calib_N_looks = cfg.fs * 2;
    V.Erfi = rfi_excise();
    V.L1 = table();  V.CAL = table();
    V.cache = struct('key', "", 'data', []);
    V.calib_base_cache = struct('dir', "", 'T', table());
    V.calib_notch_cache = struct('dir', "", 'T', table());
    V.busy = false;  V.pending = false;  V.last_n = 0;
    V.OVF = strings(0, 1);  V.OVF_ok = false;  V.OVF_src = "";
    V.cap_folders = containers.Map('KeyType', 'char', 'ValueType', 'char');
    V.ov_title = '';  V.ov_xlabel = '';  V.ov_ylabel = '';
    V.ov_plot_kind = '';
    V.U = soop_viewer_util();  V.D = soop_viewer_data();
    V.CB = soop_viewer_callbacks();
    [V.PLOT_INFO, V.CAP_PATTERNS] = soop_viewer_catalog(cfg);
    soop_viewer_layout(V);
    V.dd_domain.Value = 'sinc';
    V.dd_agg.Value = 'Raw captures';
    V.L2 = table();  V.WX = table();  V.CAND = table();
end

function V = median_viewer(tc, bases)
% Seeded viewer on cand_runs(bases), date range covering every day, daily
% filter at 06:00 with a contributor minimum of 1.
    V = seeded_viewer(tc);
    V.CAND = cand_runs(tc, bases);
    V.dp1.Value = tc.TestData.t0;
    V.dp2.Value = tc.TestData.t0 + days(numel(bases) - 1);
    V.cb_tod.Value = true;
    V.ef_tod.Value = '0600';
    V.sp_minrun.Value = 1;
end

function T = cand_runs(tc, bases)
% Per day k: a 5-capture run at 06:00:00..06:00:40 with phases
% wrap(bases(k) + [-2 -1 0 1 30]) (circular median = bases(k)), and a
% 5-capture run at 08:00 (outside +-1 h of a 06:00 target) at bases(k) + 100.
% SNR 20 everywhere; base_name d<k>_<j> (06:00) / e<k>_<j> (08:00);
% phase_raw_deg duplicates corr_41622 for the Sensor data view.
    U = tc.TestData.U;
    offs = [-2; -1; 0; 1; 30];
    t = datetime.empty(0, 1);  bn = strings(0, 1);  ph = zeros(0, 1);
    for k = 1:numel(bases)
        d = tc.TestData.t0 + days(k - 1);
        t  = [t;  d + hours(6) + seconds(0:10:40)'; d + hours(8) + seconds(0:10:40)']; %#ok<AGROW>
        bn = [bn; "d" + k + "_" + (1:5)'; "e" + k + "_" + (1:5)'];                  %#ok<AGROW>
        ph = [ph; U.wrap_deg(bases(k) + offs); U.wrap_deg(bases(k) + 100 + 0 * offs)]; %#ok<AGROW>
    end
    n = numel(t);
    T = table(t, bn, 20 * ones(n, 1), ph, ph, 'VariableNames', ...
              {'timestamp', 'base_name', 'snr_db', 'corr_41622', 'phase_raw_deg'});
end

function render(V, kind)
% Production render into a cleared panel (render_now clears it too), so the
% axes found afterwards belong to this render.
    delete(allchild(V.panel));
    soop_viewer_render_l2(V, kind);
end

function r = row(T, name)
    r = find(T.base_name == name, 1);
end

function tm = mid(tc, k)
% Midpoint of day k's 06:00 run (06:00:00 .. 06:00:40).
    tm = tc.TestData.t0 + days(k - 1) + hours(6) + seconds(20);
end

function h = phase_handle(V)
    ax = findobj(V.panel, 'Type', 'axes');
    h = findobj(ax(end), 'Type', 'line', '-or', 'Type', 'errorbar');
    h = h(end);   % first drawn: the phase series
end

function s = title_str(V)
    ax = findobj(V.panel, 'Type', 'axes');
    s = ax(end).Title.String;
end

function s = msg_str(V)
% show_msg text on a message-only render ('' when no single message).
    tx = findobj(V.panel, 'Type', 'text');
    if isscalar(tx), s = tx.String; else, s = ''; end
end

function K = MUOS5()
    K = 'L2: Candidates — MUOS-5 (41622)';
end

function K = MUOS5U()
    K = 'L2: Candidates Unwrapped — MUOS-5 (41622)';
end


% --------------------------------------------------------- one point / day

function test_median_one_point_per_day(tc)
    % One point per day: the circular median (incl. a +-180 straddling day)
    % at the run midpoint; title names the mode and contributor total;
    % last_n counts daily points.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    render(V, MUOS5());
    h = phase_handle(V);
    verifyEqual(tc, h.YData(:), [10; 100; 179], 'AbsTol', 1e-9);
    verifyEqual(tc, h.XData(:), [mid(tc, 1); mid(tc, 2); mid(tc, 3)]);
    verifyTrue(tc, contains(title_str(V), ...
        [char(8212) ' daily run median @ 06:00 (15 captures)']));
    verifyEqual(tc, V.last_n, 3);
end

function test_sensor_data_view(tc)
    % L2: Sensor data reads phase_raw_deg and collapses the same way.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.CAND.phase_raw_deg = V.CAND.phase_raw_deg + 5;
    render(V, 'L2: Sensor data');
    verifyEqual(tc, phase_handle(V).YData(:), [15; 105; -176], 'AbsTol', 1e-9);
end

function test_daily_off_plots_every_capture(tc)
    % Daily filter off: every in-range capture plots (10 per day), no
    % collapse and no daily title note.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.cb_tod.Value = false;
    render(V, MUOS5());
    verifyNumElements(tc, phase_handle(V).YData, 30);
    verifyFalse(tc, contains(title_str(V), 'daily'));
end


% ------------------------------------------------ per-capture filter / min n

function test_snr_cut_thins_run_not_day(tc)
    % A capture failing the SNR cutoff leaves its run; the day stays, with
    % the median over the remaining four ({-1,0,1,30} -> +0.5).
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.CAND.snr_db(row(V.CAND, "d1_1")) = 5;
    render(V, MUOS5());
    verifyEqual(tc, phase_handle(V).YData(:), [10.5; 100; 179], 'AbsTol', 1e-9);
    verifyTrue(tc, contains(title_str(V), '(14 captures)'));
end

function test_min_captures_drops_thin_run(tc)
    % Min captures/run 5: day 2's run keeps 4 contributors and drops (the
    % 08:00 run is outside the window).
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_minrun.Value = 5;
    V.CAND.snr_db(row(V.CAND, "d2_3")) = 5;
    render(V, MUOS5());
    h = phase_handle(V);
    verifyEqual(tc, h.YData(:), [10; 179], 'AbsTol', 1e-9);
    verifyEqual(tc, h.XData(:), [mid(tc, 1); mid(tc, 3)]);
end


% ---------------------------------------------------------- run-relative SNR

function test_relative_filter_drops_low_snr_member(tc)
    % The +30 outlier sits 10 dB below its run median: with the 5 dB median
    % filter it leaves the run ({-2,-1,0,1} -> -0.5); title notes the filter.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.CAND.snr_db(row(V.CAND, "d1_5")) = 10;
    V.cb_snrrel.Value = true;
    V.sp_snrrel_db.Value = 5;
    V.dd_snrrel_ref.Value = 'median';
    render(V, MUOS5());
    verifyEqual(tc, phase_handle(V).YData(:), [9.5; 100; 179], 'AbsTol', 1e-9);
    verifyTrue(tc, contains(title_str(V), ...
        ['SNR ' char(8805) ' run median ' char(8722) ' 5 dB']));
end

function test_relative_filter_also_plain_view(tc)
    % Daily filter off: the relative filter drops the low-SNR capture from
    % the raw series.
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    V.cb_tod.Value = false;
    V.CAND.snr_db(row(V.CAND, "d1_5")) = 10;
    V.cb_snrrel.Value = true;
    render(V, MUOS5());
    verifyNumElements(tc, phase_handle(V).YData, 9);
end

function test_relative_checked_without_snr_is_inert(tc)
    % Stale checked box on a product without snr_db: nothing filtered, no
    % title note (the render re-checks usability).
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.CAND.snr_db = [];
    V.cb_snrrel.Value = true;
    render(V, MUOS5());
    verifyEqual(tc, phase_handle(V).YData(:), [10; 100; 179], 'AbsTol', 1e-9);
    verifyFalse(tc, contains(title_str(V), ['SNR ' char(8805) ' run']));
end


% ------------------------------------------------ chain-cal / unwrap / aggs

function test_chaincal_before_median(tc)
    % Chain-cal applies per capture before the median; the unmatched
    % capture has no displayable phase and does not count as a contributor.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    bn = V.CAND.base_name(V.CAND.base_name ~= "d1_3");
    V.L2 = table(bn, 30 * ones(numel(bn), 1), zeros(numel(bn), 1), ...
                 'VariableNames', {'base_name', 'phase_corr_cal_deg', 'phase_corr_deg'});
    V.dd_method.Value = V.CHAINCAL_DATASET;
    V.sp_minrun.Value = 4;
    render(V, MUOS5());
    % Day 1 contributors {-2,-1,1,30} + 30 -> median 0 + 10 + 30.
    verifyEqual(tc, phase_handle(V).YData(:), [40; 130; -151], 'AbsTol', 1e-9);
    verifyTrue(tc, contains(title_str(V), 'phase offset cal'));
    V.sp_minrun.Value = 5;
    render(V, MUOS5());
    verifyEqual(tc, phase_handle(V).YData(:), [130; -151], 'AbsTol', 1e-9);
end

function test_unwrapped_view_unwraps_day_medians(tc)
    % Day medians stepping +150 deg/day wrap at day 3; the unwrapped view
    % unwraps the four medians (not the members).
    V = median_viewer(tc, [0 150 300 450]);
    cleanup = onCleanup(@() delete(V.fig));
    render(V, MUOS5U());
    verifyEqual(tc, phase_handle(V).YData(:), [0; 150; 300; 450], 'AbsTol', 1e-9);
end

function test_range_mean_after_collapse(tc)
    % Range mean summarizes the collapsed day medians (circular mean).
    V = median_viewer(tc, [10 20 30]);
    cleanup = onCleanup(@() delete(V.fig));
    V.dd_agg.Value = 'Range mean';
    render(V, MUOS5());
    h = phase_handle(V);
    verifyNumElements(tc, h.YData, 1);
    verifyEqual(tc, h.YData, 20, 'AbsTol', 1e-9);
end


% ------------------------------------------------------ overflow provenance

function test_overflow_included_counts_contributors(tc)
    % Exclusion off: no red marks on median points; the title counts the
    % flagged contributors. Exclusion on: they leave the median.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.OVF = ["d1_1"; "d1_2"; "e1_1"];  V.OVF_ok = true;
    render(V, MUOS5());
    verifyEmpty(tc, findobj(V.panel, 'Type', 'line', '-and', ...
                            'Color', [0.850 0.100 0.100]));
    verifyTrue(tc, contains(title_str(V), '2 overflow included'));
    V.cb_ovf.Value = true;
    render(V, MUOS5());
    verifyTrue(tc, contains(title_str(V), 'overflow excluded'));
    % Day 1 contributors {0, 1, 30} -> 1 -> 11.
    verifyEqual(tc, phase_handle(V).YData(1), 11, 'AbsTol', 1e-9);
end


% ------------------------------------------------------- downstream consumers

function test_snr_color_uses_contributor_median(tc)
    % Color-by-SNR colors each day by its contributors' median SNR; the
    % color floor stays at the applied cutoff.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    for k = 1:3
        for j = 1:5
            V.CAND.snr_db(row(V.CAND, "d" + k + "_" + j)) = 19 + j + k;
        end
    end
    V.cb_snrcolor.Value = true;
    render(V, MUOS5());
    sc = findobj(V.panel, 'Type', 'scatter');
    verifyNumElements(tc, sc, 1);
    verifyEqual(tc, sc.CData(:), [23; 24; 25], 'AbsTol', 1e-9);
    ax = findobj(V.panel, 'Type', 'axes');
    verifyEqual(tc, ax(end).CLim(1), V.U.snrcut_start(V.cfg));
end

function test_theta_from_contributors(tc)
    % The auto fringe rate uses the L2 elevation of the daily run
    % contributors (theta 30) — not the out-of-window 08:00 run (theta 60).
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    is_d = startsWith(V.CAND.base_name, "d");
    V.L2 = table(V.CAND.timestamp, V.CAND.base_name, 30 + 30 * ~is_d, ...
                 'VariableNames', {'timestamp', 'base_name', 'theta_deg'});
    render(V, MUOS5());
    verifyEqual(tc, V.ef_fringe.UserData.last_auto_mm, ...
                V.U.swe_per_fringe_mm(V.cfg.freq_hz, 90 - 30), 'RelTol', 1e-12);
end

function test_theory_first_anchor_on_first_median(tc)
    % 'First shown' anchors the theory curve to the first displayed median:
    % with flat SWE the curve is that value everywhere.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    wt = tc.TestData.t0 - hours(1) + minutes(15 * (0:300)');
    V.WX = table(wt, 50 * ones(numel(wt), 1), 'VariableNames', {'timestamp', 'swe_mm'});
    V.cb_swe.Value = true;  V.cb_theory.Value = true;
    V.dd_thanchor.Value = 'First shown';
    V.ef_fringe.Value = '400';
    V.ef_fringe.UserData = struct('is_auto', false, 'last_auto_text', '', ...
                                  'last_auto_mm', NaN);
    render(V, MUOS5());
    th = findobj(V.panel, 'Type', 'line', 'LineStyle', '--');
    verifyNumElements(tc, th, 1);
    y = th.YData(isfinite(th.YData));
    verifyNotEmpty(tc, y);
    verifyEqual(tc, y(:), 10 * ones(numel(y), 1), 'AbsTol', 1e-9);
end

function test_above_freezing_nearest_matches_midpoint(tc)
    % AboveFreezing - Nearest matches the run midpoint: a warm observation
    % 30 min after day 1's midpoint (31 min after its last capture is still
    % inside 35 min either way) draws one rule AT the midpoint.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.WX = table([mid(tc, 1) + minutes(30); mid(tc, 2) + minutes(30)], [2; -3], ...
                 'VariableNames', {'timestamp', 'airtc_c'});
    V.cb_airtc.Value = true;
    V.cb_abvfrz.Value = true;
    V.cb_abvfrz_nearest.Value = true;
    render(V, MUOS5());
    hv = findobj(V.panel, 'Type', 'constantline');
    verifyNumElements(tc, hv, 1);
    verifyEqual(tc, hv.Value, mid(tc, 1));
end

function test_above_freezing_nearest_second_temperature(tc)
    % Temp_C alone drives the rules like AirTC does; with both ticked a day
    % is warm when EITHER series' own nearest observation is warm. Day 1:
    % air warm, temp_c cold; day 2: air NaN, temp_c warm; day 3: both cold.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    tw = [mid(tc, 1); mid(tc, 2); mid(tc, 3)] + minutes(10);
    V.WX = table(tw, [2; NaN; -3], [-1; 4; -2], ...
                 'VariableNames', {'timestamp', 'airtc_c', 'temp_c'});
    V.cb_abvfrz.Value = true;
    V.cb_abvfrz_nearest.Value = true;
    V.cb_tempc.Value = true;
    render(V, MUOS5());
    hv = findobj(V.panel, 'Type', 'constantline');
    verifyNumElements(tc, hv, 1, 'Temp_C alone');
    verifyEqual(tc, hv.Value, mid(tc, 2));
    V.cb_airtc.Value = true;
    render(V, MUOS5());
    hv = findobj(V.panel, 'Type', 'constantline');
    verifyEqual(tc, sort([hv.Value])', [mid(tc, 1); mid(tc, 2)], 'either series');
    V.cb_tempc.Value = false;
    render(V, MUOS5());
    hv = findobj(V.panel, 'Type', 'constantline');
    verifyEqual(tc, [hv.Value], mid(tc, 1), 'AirTC alone');
end


% ----------------------------------------------------- stage empty messages

function test_empty_window(tc)
    % No run within +-1 h of the target.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.ef_tod.Value = '1200';
    render(V, MUOS5());
    verifyTrue(tc, startsWith(msg_str(V), 'No collection run within'));
end

function test_empty_overflow_stage(tc)
    % Every 06:00 capture flagged and excluded: the overflow stage is named.
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    V.OVF = V.CAND.base_name(startsWith(V.CAND.base_name, "d"));
    V.OVF_ok = true;  V.cb_ovf.Value = true;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), 'overflow filter removed them'));
end

function test_empty_relative_stage(tc)
    % Nonfinite SNR on every 06:00 capture: the relative stage (before the
    % absolute cutoff in pipeline order) is named.
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    V.CAND.snr_db(startsWith(V.CAND.base_name, "d")) = NaN;
    V.cb_snrrel.Value = true;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), 'their run''s median'));
end

function test_empty_cutoff_stage(tc)
    % Every 06:00 capture below the cutoff: the SNR cutoff is named.
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    V.CAND.snr_db(startsWith(V.CAND.base_name, "d")) = 5;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), 'none with valid SNR'));
end

function test_empty_phase_stage(tc)
    % Chain-cal with no L2 match for any 06:00 capture: no displayable
    % phase.
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    bn = V.CAND.base_name(startsWith(V.CAND.base_name, "e"));
    V.L2 = table(bn, 30 * ones(numel(bn), 1), zeros(numel(bn), 1), ...
                 'VariableNames', {'base_name', 'phase_corr_cal_deg', 'phase_corr_deg'});
    V.dd_method.Value = V.CHAINCAL_DATASET;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), 'displayable phase'));
end

function test_empty_min_captures_stage(tc)
    % Captures pass every filter but the run is below Min captures/run.
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_minrun.Value = 6;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), ['keeps ' char(8805) ' 6']));
end


function test_empty_combined_filters_name_first_stage(tc)
    % Overflow, relative and absolute filters all active: the message names
    % the FIRST stage (in pipeline order) that empties the selection, even
    % when later stages would also empty it on their own.
    % Fixture per case, on day 1's 06:00 run (d1_1..d1_5):
    %   A: all flagged + all below the cutoff        -> overflow
    %   B: none flagged, all nonfinite SNR (relative
    %      and cutoff both fail)                     -> relative
    %   C: half flagged, the rest below the cutoff   -> cutoff
    %   D: every filter passes, Min captures/run 6   -> min captures
    d = "d1_" + (1:5)';
    cases = {
        'overflow',  d,        5 * ones(5, 1),           'overflow filter removed them', 1
        'relative',  "none",   nan(5, 1),                'their run''s median',          1
        'cutoff',    d(1:2),   [20; 20; 5; 5; 5],        'none with valid SNR',          1
        'min_n',     "none",   20 * ones(5, 1),          ['keeps ' char(8805) ' 6'],     6
    };
    for k = 1:size(cases, 1)
        V = median_viewer(tc, 10);
        cleanup = onCleanup(@() delete(V.fig));
        for j = 1:5
            V.CAND.snr_db(row(V.CAND, d(j))) = cases{k, 3}(j);
        end
        V.OVF = cases{k, 2};  V.OVF_ok = true;  V.cb_ovf.Value = true;
        V.cb_snrrel.Value = true;
        V.sp_minrun.Value = cases{k, 5};
        render(V, MUOS5());
        verifyTrue(tc, contains(msg_str(V), cases{k, 4}), ...
            sprintf('%s: got "%s"', cases{k, 1}, msg_str(V)));
        clear cleanup
    end
end

function test_plain_view_combined_filters(tc)
    % Daily filter off: the same first-stage attribution for the plain
    % date-range view (overflow before the cutoff).
    V = median_viewer(tc, 10);
    cleanup = onCleanup(@() delete(V.fig));
    V.cb_tod.Value = false;
    V.OVF = V.CAND.base_name;  V.OVF_ok = true;  V.cb_ovf.Value = true;
    V.CAND.snr_db(:) = 5;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), 'overflow filter removed them'));
    V.cb_ovf.Value = false;
    render(V, MUOS5());
    verifyTrue(tc, contains(msg_str(V), 'none with valid SNR'));
end


% ------------------------------------------------------ side-panel Enable

function test_render_now_enable_states(tc)
    % Min captures/run: candidates with the daily filter off -> visible,
    % disabled; on -> enabled; within-run scatter -> enabled; value persists. The
    % relative-SNR controls follow snr_db usability.
    V = median_viewer(tc, [10 100 179]);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_minrun.Value = 7;
    V.cb_tod.Value = false;
    V.dd_plot.Value = MUOS5U();
    V.CB.render_now(V);
    verifyTrue(tc, logical(V.minrun_row.Visible));
    verifyFalse(tc, logical(V.sp_minrun.Enable));
    verifyTrue(tc, logical(V.snrrel_row.Visible));
    verifyTrue(tc, logical(V.cb_snrrel.Enable));
    verifyTrue(tc, logical(V.sp_snrrel_db.Enable));
    verifyTrue(tc, logical(V.dd_snrrel_ref.Enable));
    V.cb_tod.Value = true;
    V.CB.render_now(V);
    verifyTrue(tc, logical(V.sp_minrun.Enable));
    T = V.CAND;  T.snr_db = [];  V.CAND = T;
    V.CB.render_now(V);
    verifyFalse(tc, logical(V.cb_snrrel.Enable));
    verifyFalse(tc, logical(V.sp_snrrel_db.Enable));
    verifyFalse(tc, logical(V.dd_snrrel_ref.Enable));
    V.L1 = table(V.CAND.timestamp, V.CAND.base_name, V.CAND.corr_41622, ...
                 20 * ones(height(V.CAND), 1), 'VariableNames', ...
                 {'timestamp', 'base_name', 'peak_phase_deg', 'snr_db'});
    V.cb_tod.Value = false;
    V.dd_plot.Value = 'L1: Within-run phase scatter';
    V.CB.render_now(V);
    verifyTrue(tc, logical(V.minrun_row.Visible));
    verifyTrue(tc, logical(V.sp_minrun.Enable));
    verifyTrue(tc, logical(V.snrrel_row.Visible));
    verifyTrue(tc, logical(V.cb_snrrel.Enable));
    verifyEqual(tc, V.sp_minrun.Value, 7);
end
