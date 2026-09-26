function tests = viewer_wrscatter_test
% Unit tests for the 'L1: Within-run phase scatter' view: the snowfall_mask /
% snowfall_usable helpers, the capture filters (SNR cutoff, minimum
% captures per run), color-by-SNR, the stacked weather panels and snowfall
% shading, and CB.render_now row visibility / Enable gating.
% Run: matlab -batch "soop_setup_paths; addpath('tests'); runtests('viewer_wrscatter_test')"
    tests = functiontests(localfunctions);
end


function setupOnce(tc)
    tc.TestData.U   = soop_viewer_util();
    tc.TestData.t0  = datetime(2026, 1, 1);
    f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    tc.TestData.dir = f.Folder;
end


function V = seeded_viewer(tc)
    % Real viewer state + layout (headless), mirroring viewer_ovf_filter_test.
    cfg = struct('freq_hz', 370e6, 'fs', 20e6, 'num_segs', 2, 'Ti', 0.9, ...
                 'peak_lag', -0.575, 'T_load_K', 290, ...
                 'out_dir', tc.TestData.dir, 'data_dir', tc.TestData.dir);
    V = SoopViewerState();
    V.cfg = cfg;
    V.M   = BrundageSoOp_fun();
    V.npts = floor(cfg.fs * cfg.Ti);  V.n_want = V.npts * cfg.num_segs;
    V.calib_N_looks = cfg.fs * 2;
    V.Erfi = rfi_excise();
    V.L1 = table();  V.CAL = table();
    V.cache = struct('key', "", 'data', []);
    V.calib_base_cache  = struct('dir', "", 'T', table());
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


function T = l1_runs(tc)
    % Three runs 2 h apart. Run 1: 10 captures at 0 deg / 25 dB plus 2 at
    % 90 deg / 5 dB (std collapses to 0 once a 10 dB cutoff removes them).
    % Run 2: 12 captures at 10 deg / 20 dB. Run 3: 4 captures (hidden by the
    % default 10-capture minimum).
    t0 = tc.TestData.t0;
    t = [t0 + seconds(10 * (0:11)), t0 + hours(2) + seconds(10 * (0:11)), ...
         t0 + hours(4) + seconds(10 * (0:3))]';
    ph  = [zeros(1, 10), 90, 90, 10 * ones(1, 12), 5 * ones(1, 4)]';
    snr = [25 * ones(1, 10), 5, 5, 20 * ones(1, 12), 30 * ones(1, 4)]';
    T = table(t, "cap_" + string((1:numel(t))'), ph, snr, ...
              'VariableNames', {'timestamp', 'base_name', 'peak_phase_deg', 'snr_db'});
end

function WX = wx_day(tc)
    % 15-min weather: SWE +3 mm/h and depth +1 cm/h from 06:00 to 12:00
    % (snowing), flat otherwise. AirTC -0.5 C before 09:00 (wet), -5 C after
    % (cold). Wind 2 m/s.
    t = (tc.TestData.t0 - hours(3) : minutes(15) : tc.TestData.t0 + hours(27))';
    h = hours(t - tc.TestData.t0);
    acc = min(max(h - 6, 0), 6);            % hours of snowfall so far
    swe   = 100 + 3 * acc;
    depth = 0.5 + 0.01 * acc;
    airtc = -0.5 * ones(size(t));  airtc(h >= 9) = -5;
    WX = table(t, depth, airtc, airtc, swe, 2 * ones(size(t)), ...
        'VariableNames', {'timestamp', 'depth_m', 'airtc_c', 'temp_c', 'swe_mm', 'wind_ms'});
end

function V = wr_viewer(tc)
    V = seeded_viewer(tc);
    V.L1 = l1_runs(tc);
    V.dp1.Value = tc.TestData.t0;
    V.dp2.Value = tc.TestData.t0 + days(1);
    V.cb_ovf.Value = false;
end

function ax = main_ax(V)
    axs = findobj(V.panel, 'Type', 'axes');
    ax = axs(end);                          % first created = top panel
end

function sd = run_ydata(V)
    ax = main_ax(V);
    h = [findobj(ax, 'Type', 'line'); findobj(ax, 'Type', 'scatter')];
    sd = h(1).YData(:);
end

function at = wx_row(WX, tc, hh)
    at = find(WX.timestamp == tc.TestData.t0 + hours(hh), 1);
end


% ------------------------------------------------------------ snowfall_mask

function test_snowfall_mask_classes(tc)
    % Snowing 06:00-12:00: wet while AirTC is -0.5 C (before 09:00), cold
    % after; outside the snowfall both classes are 0.
    WX = wx_day(tc);
    [wet, cold] = tc.TestData.U.snowfall_mask(WX.timestamp, WX.airtc_c, WX.swe_mm, WX.depth_m);
    verifyEqual(tc, [wet(wx_row(WX, tc, 8)),  cold(wx_row(WX, tc, 8))],  [1 0]);
    verifyEqual(tc, [wet(wx_row(WX, tc, 11)), cold(wx_row(WX, tc, 11))], [0 1]);
    verifyEqual(tc, [wet(wx_row(WX, tc, 18)), cold(wx_row(WX, tc, 18))], [0 0]);
end

function test_snowfall_mask_needs_both_sensors(tc)
    % SWE rising with flat depth (rain absorbed by the pack) is not
    % snowfall; a missing depth or AirTC record leaves the sample NaN
    % (unclassifiable), never 0.
    U = tc.TestData.U;
    WX = wx_day(tc);
    at = wx_row(WX, tc, 8);
    flat = 0.5 * ones(height(WX), 1);
    [wet, cold] = U.snowfall_mask(WX.timestamp, WX.airtc_c, WX.swe_mm, flat);
    verifyEqual(tc, [wet(at), cold(at)], [0 0]);
    wet = U.snowfall_mask(WX.timestamp, WX.airtc_c, WX.swe_mm, nan(height(WX), 1));
    verifyTrue(tc, isnan(wet(at)));
    air = WX.airtc_c;  air(at) = NaN;
    [wet2, cold2] = tc.TestData.U.snowfall_mask(WX.timestamp, air, WX.swe_mm, WX.depth_m);
    verifyTrue(tc, isnan(wet2(at)) && isnan(cold2(at)));
end

function test_snowfall_usable_gate(tc)
    U = tc.TestData.U;
    WX = wx_day(tc);
    verifyTrue(tc, U.snowfall_usable(WX));
    verifyFalse(tc, U.snowfall_usable(table()));
    W2 = WX;  W2.depth_m(:) = NaN;
    verifyFalse(tc, U.snowfall_usable(W2));
    WX.airtc_c(:) = NaN;
    verifyFalse(tc, U.snowfall_usable(WX));
end


% ------------------------------------------------------------------ render

function test_min_captures_hides_short_run(tc)
    % Default minimum (10) hides the 4-capture run;
    % minimum 1 plots all three runs.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_snrcut.Value = 0;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    verifyNumElements(tc, run_ydata(V), 2);
    V.sp_minrun.Value = 1;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    verifyNumElements(tc, run_ydata(V), 3);
end

function test_snr_cutoff_before_std(tc)
    % SNR cutoff 0 dB keeps run 1's two 90 deg / 5 dB captures (std > 0);
    % 10 dB drops them before the std, collapsing run 1 to 0 deg.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_snrcut.Value = 0;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    sd = run_ydata(V);
    verifyGreaterThan(tc, sd(1), 1);
    V.sp_snrcut.Value = 10;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    sd = run_ydata(V);
    verifyEqual(tc, sd(1), 0, 'AbsTol', 1e-6);
end

function test_snr_color(tc)
    % Color-by-SNR draws a scatter whose CData is each run's median SNR of
    % the kept captures, with an SNR colorbar.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_snrcut.Value = 10;
    V.cb_snrcolor.Value = true;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    h = findobj(main_ax(V), 'Type', 'scatter');
    verifyNumElements(tc, h, 1);
    verifyEqual(tc, h.CData(:), [25; 20]);
    cb = findobj(V.fig, 'Type', 'colorbar');
    verifyEqual(tc, cb.Label.String, 'Median run SNR [dB]');
end

function test_hour_color(tc)
    % Color-by-hour draws a scatter whose CData is each run's start-hour bin
    % center (runs start 00:00 and 02:00), with a cyclic 0-24 color scale;
    % hour wins if both color boxes are set.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.sp_snrcut.Value = 10;
    V.cb_hourcolor.Value = true;
    V.cb_snrcolor.Value = true;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    h = findobj(main_ax(V), 'Type', 'scatter');
    verifyNumElements(tc, h, 1);
    verifyEqual(tc, h.CData(:), [0.5; 2.5]);
    verifyEqual(tc, clim(main_ax(V)), [0 24]);
    cb = findobj(V.fig, 'Type', 'colorbar');
    verifyEqual(tc, cb.Label.String, 'Run start hour (capture clock)');
end

function test_weather_panels_and_shading(tc)
    % Depth + SWE share one panel (two rulers), AirTC one panel, wind one
    % panel: four linked axes. Wet and cold shading each add one region
    % per axes and a legend entry on the top panel.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.WX = wx_day(tc);
    V.sp_snrcut.Value = 0;
    V.cb_depth.Value = true;  V.cb_swe.Value = true;
    V.cb_airtc.Value = true;  V.cb_tempc.Value = false;
    V.cb_wind.Value = true;
    V.cb_wetsnow.Value = true;  V.cb_coldsnow.Value = true;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    axs = findobj(V.panel, 'Type', 'axes');
    verifyNumElements(tc, axs, 4);
    verifyEqual(tc, axs(1).YLabel.String, 'Wind (m/s)');
    for k = 1:numel(axs)
        verifyNumElements(tc, findobj(axs(k), 'Type', 'constantregion'), 2);
    end
    lg = findobj(V.fig, 'Type', 'legend');
    top = lg(arrayfun(@(l) l.Axes == main_ax(V), lg));
    verifyTrue(tc, any(startsWith(top.String, 'Wet snowfall')));
    verifyTrue(tc, any(startsWith(top.String, 'Cold snowfall')));
end

function test_no_weather_single_panel(tc)
    % Weather boxes ticked with no weather table: one axes, no shading.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.cb_depth.Value = true;  V.cb_wetsnow.Value = true;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    axs = findobj(V.panel, 'Type', 'axes');
    verifyNumElements(tc, axs, 1);
    verifyEmpty(tc, findobj(axs, 'Type', 'constantregion'));
end


% ------------------------------------------------------------- render_now

function test_render_now_rows_and_enable(tc)
    % Within-run scatter shows its own rows plus the shared weather,
    % SNR-cutoff and color rows; snowfall / wind Enable follows the weather
    % table. Another L1 view hides the view-specific rows.
    V = wr_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.cb_depth.Value = true;  V.cb_wind.Value = true;  V.sp_ptsz.Value = 1;
    V.dd_plot.Value = 'L1: Within-run phase scatter';
    V.CB.render_now(V);
    % Opening the view unticks the weather panels and sets Pt x to 3; a
    % later re-render keeps the user's choices.
    verifyFalse(tc, V.cb_depth.Value || V.cb_swe.Value || V.cb_airtc.Value || ...
                    V.cb_tempc.Value || V.cb_wind.Value);
    verifyEqual(tc, V.sp_ptsz.Value, 3);
    V.cb_depth.Value = true;  V.sp_ptsz.Value = 2;
    V.CB.render_now(V);
    verifyTrue(tc, V.cb_depth.Value);
    verifyEqual(tc, V.sp_ptsz.Value, 2);
    verifyTrue(tc, logical(V.hour_row.Visible));
    verifyTrue(tc, logical(V.cb_hourcolor.Enable));
    verifyTrue(tc, logical(V.minrun_row.Visible));
    verifyTrue(tc, logical(V.snowfall_row.Visible));
    verifyTrue(tc, logical(V.wind_row.Visible));
    verifyTrue(tc, logical(V.snrcut_row.Visible));
    verifyTrue(tc, logical(V.snrcolor_row.Visible));
    verifyTrue(tc, logical(V.cb_swe.Visible));
    verifyTrue(tc, logical(V.sp_snrcut.Enable));
    verifyFalse(tc, logical(V.cb_wetsnow.Enable));
    verifyFalse(tc, logical(V.cb_wind.Enable));
    V.WX = wx_day(tc);
    V.CB.render_now(V);
    verifyTrue(tc, logical(V.cb_wetsnow.Enable));
    verifyTrue(tc, logical(V.cb_wind.Enable));
    V.dd_plot.Value = 'L1: SNR time series';
    V.CB.render_now(V);
    verifyFalse(tc, logical(V.minrun_row.Visible));
    verifyFalse(tc, logical(V.snowfall_row.Visible));
    verifyFalse(tc, logical(V.cb_swe.Visible));
end


% ------------------------------------------------------- run-relative SNR

function T = l1_snr_runs(tc, t, ph, snr)
% L1 rows at times t with sinc phases ph and SNR snr.
    n = numel(t);
    T = table(t(:), "cap_" + string((1:n)'), ph(:), snr(:), 'VariableNames', ...
              {'timestamp', 'base_name', 'peak_phase_deg', 'snr_db'});
end

function test_relative_filter_drops_low_snr_capture(tc)
    % Run 1 {0,0,0,90}: the 90 deg capture sits 10 dB below the run median,
    % so the 5 dB median filter removes it and the run std falls to 0.
    t0 = tc.TestData.t0;
    t = [t0 + hours(6) + seconds(0:10:30), t0 + hours(8) + seconds(0:10:30)];
    V = seeded_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.L1 = l1_snr_runs(tc, t, [0 0 0 90 10 10 10 10], [20 20 20 10 20 20 20 20]);
    V.dp1.Value = t0;  V.dp2.Value = t0;
    V.dd_domain.Value = 'sinc';
    V.sp_minrun.Value = 1;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    sd = run_ydata(V);
    verifyGreaterThan(tc, sd(1), 1);
    V.cb_snrrel.Value = true;
    V.sp_snrrel_db.Value = 5;
    V.dd_snrrel_ref.Value = 'median';
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    verifyEqual(tc, run_ydata(V), [0; 0], 'AbsTol', 1e-6);
end

function test_relative_reference_spans_range_boundary(tc)
    % A run crossing the range start: its pre-range captures (SNR 50) set
    % the max reference, so the in-range 44 dB capture (phase 90) drops at
    % 5 dB; an in-range-only reference (46) would keep it.
    t0 = tc.TestData.t0;
    t = [t0 - seconds([20 10]), t0 + seconds([0 10 20])];
    V = seeded_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.L1 = l1_snr_runs(tc, t, [0 0 90 0 0], [50 50 44 46 46]);
    V.dp1.Value = t0;  V.dp2.Value = t0;
    V.dd_domain.Value = 'sinc';
    V.sp_minrun.Value = 1;
    V.cb_snrrel.Value = true;
    V.sp_snrrel_db.Value = 5;
    V.dd_snrrel_ref.Value = 'max';
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    verifyEqual(tc, run_ydata(V), 0, 'AbsTol', 1e-6);
end

function test_filtered_bridge_keeps_run_identity(tc)
    % Captures at 0 / 20 / 40 min form ONE run (no gap > 30 min). The SNR
    % cutoff removes the 20-min bridge: the survivors keep the full-table run
    % id, so one run of 2 captures (std of {0, 60}, start at 0 min) plots
    % with Min captures/run 2, rather than two 1-capture runs being hidden.
    t0 = tc.TestData.t0;
    t = t0 + hours(6) + minutes([0 20 40]);
    V = seeded_viewer(tc);
    cleanup = onCleanup(@() delete(V.fig));
    V.L1 = l1_snr_runs(tc, t, [0 30 60], [20 5 20]);
    V.dp1.Value = t0;  V.dp2.Value = t0;
    V.dd_domain.Value = 'sinc';
    V.sp_minrun.Value = 2;
    V.sp_snrcut.Value = 10;
    soop_viewer_render_l1(V, 'L1: Within-run phase scatter');
    ax = main_ax(V);
    h = [findobj(ax, 'Type', 'line'); findobj(ax, 'Type', 'scatter')];
    verifyNumElements(tc, h(1).YData, 1, 'one run plotted');
    [~, sd] = V.M.circ_stats([0; 60]);
    verifyEqual(tc, h(1).YData(1), sd, 'AbsTol', 1e-9);
    verifyEqual(tc, h(1).XData(1), t(1));
end
