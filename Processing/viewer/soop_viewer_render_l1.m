function soop_viewer_render_l1(V, kind)
% L1 CSV plot family + 'Data availability' + the 'Lag:' peak-lag diagnostic.
% One public entry; render_now routes both 'Lag:*' and 'L1:*'/'Data' here.
    if startsWith(kind, 'Lag:')
        render_lag(V, kind);
    else
        render_l1(V, kind);
    end
end


function render_lag(V, ~)
    S = V;
    cfg = V.cfg;
    show_msg = @(varargin) V.U.show_msg(V, varargin{:});
    range_bounds = @(varargin) V.U.range_bounds(V, varargin{:});
    tcol = V.U.tcol;
    dataset_label = @(varargin) V.U.dataset_label(V, varargin{:});
    % Measured peak-lag index over time: Signal (meas_peak_lag, L1 CSV) plus
    % the NL / L calibration captures (nl_peak_lag / l_peak_lag, calib CSV)
    % for the active Dataset. Diagnostic only — the observable is the phase
    % at the fixed cfg.peak_lag, not this argmax.
    [t0, t1] = range_bounds();
    has_sig = ~isempty(S.L1)  && ismember('meas_peak_lag', S.L1.Properties.VariableNames);
    has_cal = ~isempty(S.CAL) && ismember('nl_peak_lag',  S.CAL.Properties.VariableNames);
    if ~has_sig && ~has_cal
        show_msg(['No measured peak-lag columns in this dataset (' ...
                  char(dataset_label()) '). Re-run compute_L1 (adds ' ...
                  'meas_peak_lag) and compute_calib (adds nl_peak_lag / ' ...
                  'l_peak_lag), then Reload.']);
        return;
    end

    % Collect the series present: {label, t, lag}.
    ser = cell(0, 3);
    if has_sig
        Ts = S.L1(tcol(S.L1) >= t0 & tcol(S.L1) < t1, :);
        ser(end+1, :) = {'Signal', tcol(Ts), Ts.meas_peak_lag};
    end
    if has_cal
        Tc = S.CAL(tcol(S.CAL) >= t0 & tcol(S.CAL) < t1, :);
        ser(end+1, :) = {'NL', tcol(Tc), Tc.nl_peak_lag};
        ser(end+1, :) = {'L',  tcol(Tc), Tc.l_peak_lag};
    end

    tl = tiledlayout(S.panel, 1, 1);
    ax = nexttile(tl);
    hold(ax, 'on');
    cmap = lines(7);
    leg  = strings(1, size(ser, 1));
    ally = [];
    ntot = 0;
    stat_lines = strings(0, 1);
    for i = 1:size(ser, 1)
        nm = ser{i, 1};  ti = ser{i, 2};  yi = double(ser{i, 3});
        ok = ~isnan(yi);  ti = ti(ok);  yi = yi(ok);
        plot(ax, ti, yi, '.', 'Color', cmap(i, :), 'MarkerSize', 9);
        n = numel(yi);  ntot = ntot + n;
        ally = [ally; yi]; %#ok<AGROW>
        if n > 0
            leg(i) = sprintf('%s (n=%d, %.0f%% @0)', nm, n, 100*mean(yi == 0));
            u  = unique(yi);
            cc = arrayfun(@(v) sum(yi == v), u);
            pr = arrayfun(@(v, c) sprintf('%+d:%d', v, c), u, cc, 'UniformOutput', false);
            stat_lines(end+1) = string(nm) + " — " + strjoin(string(pr), "  "); %#ok<AGROW>
        else
            leg(i) = sprintf('%s (no rows)', nm);
        end
    end
    S.last_n = ntot;

    grid(ax, 'on');
    ylabel(ax, 'Measured peak-lag (samples)');
    xlabel(ax, 'Capture time');
    if ~isempty(ally)
        lo = min(ally) - 1;  hi = max(ally) + 1;
        ylim(ax, [lo hi]);  yticks(ax, floor(lo):ceil(hi));
    end
    title(ax, "Measured cross-correlation peak-lag index — " + dataset_label());
    subtitle(ax, "Diagnostic only; observable phase read at fixed peak\_lag = " + ...
             sprintf('%.3f', cfg.peak_lag));
    legend(ax, leg, 'Location', 'best');

    % Per-series integer-lag counts, top-left corner of the axes.
    if ~isempty(stat_lines)
        text(ax, 0.01, 0.99, "Counts by lag:" + newline + strjoin(stat_lines, newline), ...
             'Units', 'normalized', 'VerticalAlignment', 'top', ...
             'HorizontalAlignment', 'left', 'FontName', 'monospaced', ...
             'FontSize', 9, 'BackgroundColor', [1 1 1], 'Interpreter', 'none');
    end
end


function render_l1(V, kind)
    S = V;
    cfg = V.cfg;
    M = V.M;
    show_msg = @(varargin) V.U.show_msg(V, varargin{:});
    range_bounds = @(varargin) V.U.range_bounds(V, varargin{:});
    tcol = V.U.tcol;
    plot_domain_series = @(varargin) V.U.plot_domain_series(V, varargin{:});
    domain_suffix = @(varargin) V.U.domain_suffix(V, varargin{:});
    plot_series = @(varargin) V.U.plot_series(V, varargin{:});
    domain_cols = @(varargin) V.U.domain_cols(V, varargin{:});
    domain_color = V.U.domain_color;
    if isempty(S.L1)
        show_msg(sprintf('No L1 CSV found in %s', cfg.out_dir));
        return;
    end
    [t0, t1] = range_bounds();
    T = S.L1(tcol(S.L1) >= t0 & tcol(S.L1) < t1, :);
    if isempty(T)
        show_msg('No L1 rows in the selected date range.');
        return;
    end
    S.last_n = height(T);
    if strcmp(kind, 'L1: Within-run phase scatter')
        render_wrscatter(V, T, t0, t1);
        return;
    end
    t   = tcol(T);
    agg = S.dd_agg.Value;
    tl  = tiledlayout(S.panel, 1, 1);
    ax  = nexttile(tl);

    switch kind
        case 'L1: Phase time series'
            plot_domain_series(ax, t, T, 'peak_phase_deg', 'peak_phase_deg_fd', ...
                               'peak_phase_deg_fd_muos', agg, 'phase');
            ylabel(ax, 'Phase (deg)');  ylim(ax, [-180 180]);  yticks(ax, -180:90:180);
            title(ax, ['Cross-correlation phase at peak\_lag (the snow observable, wrapped)' ...
                       domain_suffix()]);
        case 'L1: SNR time series'
            plot_series(ax, t, T.snr_db, agg, 'db');
            ylabel(ax, 'SNR (dB)');  title(ax, 'Peak SNR');
        case 'L1: Amplitude time series'
            plot_domain_series(ax, t, T, 'peak_amplitude', 'peak_amplitude_fd', ...
                               'peak_amplitude_fd_muos', agg, 'lin');
            ylabel(ax, 'Amplitude (ADC units)');
            title(ax, ['Coherent reflection amplitude' domain_suffix()]);
        case 'L1: Noise floor time series'
            plot_series(ax, t, T.noise_floor, agg, 'lin');
            ylabel(ax, 'Noise floor (ADC units)');  title(ax, 'Correlation noise floor');
        case 'L1: SNR histogram'
            histogram(ax, T.snr_db, 60);
            xlabel(ax, 'SNR (dB)');  ylabel(ax, 'Count');
            title(ax, sprintf('SNR distribution, %d captures in range', height(T)));
        case 'L1: Phase vs SNR scatter'
            [cols, labs] = domain_cols(T, 'peak_phase_deg', 'peak_phase_deg_fd', ...
                                       'peak_phase_deg_fd_muos');
            hold(ax, 'on');
            hh = gobjects(numel(cols), 1);
            for ii = 1:numel(cols)
                hh(ii) = scatter(ax, T.snr_db, T.(cols{ii}), 6, 'filled', ...
                    'MarkerFaceAlpha', 0.25, 'MarkerFaceColor', domain_color(labs{ii}));
            end
            hold(ax, 'off');
            if numel(cols) > 1, legend(hh, labs, 'Location', 'best'); end
            xlabel(ax, 'SNR (dB)');  ylabel(ax, 'Phase (deg)');
            ylim(ax, [-180 180]);  yticks(ax, -180:90:180);
            title(ax, ['Phase vs SNR — does low SNR mean phase scatter?' domain_suffix()]);
        case 'L1: Diurnal phase pattern'
            hr = hour(t);
            % When Detrend is ticked, subtract each day's circular mean from its
            % captures before binning, so the seasonal wander S(day) (common to
            % all hours within a day) is removed and only the diurnal residual
            % remains. This is the clean test for a real (vs. coverage-aliased)
            % hour-of-day signal.
            detrend_on = S.sw_detrend.Value;
            if detrend_on, day_grp = findgroups(dateshift(t, 'start', 'day')); end
            [cols, labs] = domain_cols(T, 'peak_phase_deg', 'peak_phase_deg_fd', ...
                                       'peak_phase_deg_fd_muos');
            hold(ax, 'on');
            hh = gobjects(numel(cols), 1);
            for ii = 1:numel(cols)
                yc = T.(cols{ii});
                if detrend_on
                    mu_day = splitapply(@(x) M.first_out(M.circ_stats, x), yc, day_grp);
                    % Wrapped residual (deg): complex round-trip keeps it in ±180.
                    yc = rad2deg(angle(exp(1i * deg2rad(yc - mu_day(day_grp)))));
                end
                [mu, sd] = deal(nan(24, 1));
                for h = 0:23
                    x = yc(hr == h);
                    if ~isempty(x), [mu(h+1), sd(h+1)] = M.circ_stats(x); end
                end
                hh(ii) = errorbar(ax, 0:23, mu, sd, 'o-', 'Color', domain_color(labs{ii}));
            end
            hold(ax, 'off');
            if numel(cols) > 1, legend(hh, labs, 'Location', 'best'); end
            xlabel(ax, 'Hour of day (capture timestamp — Pi clock timezone)');
            xlim(ax, [-0.5 23.5]);
            if detrend_on
                ylabel(ax, 'Residual phase \pm circ. std (deg), daily mean removed');
                title(ax, ['Diurnal phase RESIDUAL (daily circ. mean removed)' domain_suffix()]);
            else
                ylabel(ax, 'Circular mean phase \pm circ. std (deg)');
                title(ax, ['Diurnal phase pattern (melt-freeze cycling)' domain_suffix()]);
            end
        case 'L1: Peak-bin vs elevation (QA)'
            if isempty(S.L2)
                show_msg('Needs BrundageSoOp_L2.csv (run compute_L2) for elevation.');
                return;
            end
            if ~all(ismember({'base_name', 'meas_peak_lag'}, ...
                    T.Properties.VariableNames))
                show_msg(['Peak-bin vs elevation needs base_name + ' ...
                          'meas_peak_lag in L1 — re-run compute_L1.']);
                return;
            end
            % Filter BOTH tables to the date range BEFORE join, then
            % inner-join on base_name. Only captures in both L1 and L2 appear.
            L2r = S.L2(tcol(S.L2) >= t0 & tcol(S.L2) < t1, :);
            if isempty(L2r) || ~all(ismember({'base_name', 'theta_deg'}, ...
                    L2r.Properties.VariableNames))
                show_msg(['Peak-bin vs elevation needs base_name + theta_deg ' ...
                          'in L2 (in range) — re-run compute_L2.']);
                return;
            end
            J = innerjoin(T(:, {'base_name', 'meas_peak_lag'}), ...
                          L2r(:, {'base_name', 'theta_deg'}), 'Keys', 'base_name');
            th = J.theta_deg;  pl = J.meas_peak_lag;
            fin = isfinite(th) & isfinite(pl);
            th = th(fin);  pl = pl(fin);
            if isempty(th)
                show_msg('No captures present in both L1 and L2 (in range).');
                return;
            end
            hold(ax, 'on');
            hs = scatter(ax, th, pl, 10, 'filled', 'MarkerFaceAlpha', 0.25);
            lh = hs;  ls = {'per capture'};
            if max(th) > min(th)            % binned median (gross trend QA)
                edges = linspace(min(th), max(th), 13);
                bc    = 0.5 * (edges(1:end-1) + edges(2:end));
                bidx  = discretize(th, edges);
                bmed  = nan(numel(bc), 1);
                for b = 1:numel(bc)
                    bmed(b) = median(pl(bidx == b), 'omitnan');
                end
                hb = plot(ax, bc, bmed, 'o-', 'Color', [0.85 0.1 0.1], ...
                          'LineWidth', 1.2, 'MarkerFaceColor', [0.85 0.1 0.1]);
                lh(end+1) = hb;  ls{end+1} = 'binned median';
            end
            yline(ax, cfg.peak_lag, '--', sprintf(['fixed fractional ' ...
                'extraction lag (%.3f; sub-sample, not comparable to ' ...
                'integer bins)'], cfg.peak_lag), 'Color', [0.3 0.3 0.3], ...
                'LabelHorizontalAlignment', 'left');
            hold(ax, 'off');
            legend(lh, ls, 'Location', 'best');
            xlabel(ax, 'Satellite elevation \theta (deg)');
            ylabel(ax, 'Measured peak-lag bin (integer argmax, samples)');
            title(ax, sprintf(['Peak-bin vs elevation QA (n=%d; integer ' ...
                'argmax — gross check, not sub-sample drift)'], numel(th)));
        case 'Data availability'
            day_key = dateshift(t, 'start', 'day');
            is_ovf  = ismember(T.base_name, S.OVF);
            [gd, days_u] = findgroups(day_key);
            n_clean = splitapply(@(x) sum(~x), is_ovf, gd);
            n_ovf   = splitapply(@(x) sum(x),  is_ovf, gd);
            hb = bar(ax, days_u, [n_clean, n_ovf], 1, 'stacked');
            hb(1).FaceColor = [0.000 0.447 0.741];   % clean
            hb(2).FaceColor = [0.850 0.100 0.100];   % overflow-flagged
            yline(ax, 180, '--', 'expected (12 runs x 15)');
            legend(ax, {'clean', 'overflow-flagged'}, 'Location', 'best');
            ylabel(ax, 'Captures per day');
            if isempty(S.OVF)
                title(ax, 'Data availability (no overflow_timestamps.txt found)');
            else
                title(ax, sprintf('Data availability — %d overflow-flagged in range', ...
                      sum(is_ovf)));
            end
    end
    grid(ax, 'on');
end


function render_wrscatter(V, ~, t0, t1)
% Within-run phase scatter: circular std (deg) of each 2-hourly run's
% captures, one point per run at the run start. Runs are identified on the
% full L1 table (S.L1); the filters (overflow exclusion, run-relative SNR, SNR
% cutoff) then drop captures from them without splitting a run, the [t0,t1)
% captures are kept, and runs keeping fewer than the minimum captures are
% hidden. Optional
% stacked weather panels (depth / SWE, temperatures, wind) share the linked
% time axis, and
% wet / cold snowfall spans shade every panel.
    S = V;
    M = V.M;
    tcol = V.U.tcol;
    show_msg = @(varargin) V.U.show_msg(V, varargin{:});
    domain_suffix = @(varargin) V.U.domain_suffix(V, varargin{:});
    domain_cols = @(varargin) V.U.domain_cols(V, varargin{:});
    domain_color = V.U.domain_color;
    C = SoopViewerState;

    %% Capture filters (overflow exclusion, run-relative SNR, SNR cutoff)
    % Run ids come from the FULL L1 table and are carried through row masks
    % applied in pipeline order, then the date range (T is its in-range
    % subset), so removing a capture never splits or renumbers a run. The
    % run-relative reference — the run's median or max SNR over its
    % post-overflow rows, before the absolute cutoff — spans whole runs; the
    % per-run statistics below use only the in-range captures that pass. A
    % checked-but-disabled relative box (no usable snr_db) is inert.
    L   = S.L1;
    grp_all = M.run_groups(tcol(L));
    inr = tcol(L) >= t0 & tcol(L) < t1;
    keep = true(height(L), 1);
    if S.cb_ovf.Value && V.U.ovf_usable(L, S.OVF_ok)
        keep = ~V.U.ovf_mask(L, S.OVF);
    end
    rel_on = false;
    if S.cb_snrrel.Value && V.U.snrcut_usable(L)
        [kr, rel_on] = V.U.snrrel_keep(L.snr_db(keep), grp_all(keep), ...
            S.sp_snrrel_db.Value, char(S.dd_snrrel_ref.Value));
        if rel_on, keep(keep) = kr; end
    end
    snr_cut = S.sp_snrcut.Value;
    [~, snr_ok, k_snr] = V.U.snrcut_apply(L, snr_cut);
    sel = inr & keep & k_snr;
    T = L(sel, :);
    if isempty(T)
        if rel_on
            show_msg(['No captures in the selected range pass the SNR / ' ...
                      'run-relative SNR / overflow filters.']);
        else
            show_msg('No captures in the selected range pass the SNR / overflow filters.');
        end
        return;
    end

    %% Runs and per-run statistics
    % Carried full-table run ids, compacted to 1..n in chronological order
    % for splitapply.
    t = tcol(T);
    [~, ~, grp] = unique(grp_all(sel));
    t_run = splitapply(@min, t, grp);
    n_run = splitapply(@numel, t, grp);
    keep = n_run >= S.sp_minrun.Value;
    if ~any(keep)
        show_msg(sprintf('No run keeps >= %d captures after the filters.', ...
                         S.sp_minrun.Value));
        return;
    end
    [cols, labs] = domain_cols(T, 'peak_phase_deg', 'peak_phase_deg_fd', ...
                               'peak_phase_deg_fd_muos');
    % Point coloring: nearest hour of day of the run start (capture clock),
    % or median run SNR (dB) of the kept captures. The two are mutually
    % exclusive (on_pointcolor); hour wins if both are somehow set.
    hour_on = S.cb_hourcolor.Value;
    snr_on  = S.cb_snrcolor.Value && ~hour_on && V.U.snrcut_usable(T);
    if hour_on
        cval = V.U.hour_bins(t_run) + 0.5;
    elseif snr_on
        cval = splitapply(@(x) median(x, 'omitnan'), T.snr_db, grp);
    end
    color_on = hour_on || snr_on;

    %% Weather panels and snowfall shading requested
    WX = S.WX;
    has_wx = @(c) ~isempty(WX) && istable(WX) && ...
                  ismember(c, WX.Properties.VariableNames);
    if has_wx('timestamp')
        TW = WX(tcol(WX) >= t0 & tcol(WX) < t1, :);
    else
        TW = table();
    end
    fin = @(c) has_wx(c) && ~isempty(TW) && any(isfinite(TW.(c)));
    show_dep  = S.cb_depth.Value && fin('depth_m');
    show_swe  = S.cb_swe.Value   && fin('swe_mm');
    show_air  = S.cb_airtc.Value && fin('airtc_c');
    show_tmp  = S.cb_tempc.Value && fin('temp_c');
    show_wind = S.cb_wind.Value  && fin('wind_ms');
    shade_ok  = V.U.snowfall_usable(WX);
    want_wet  = S.cb_wetsnow.Value  && shade_ok;
    want_cold = S.cb_coldsnow.Value && shade_ok;
    tiles = {};
    if show_dep || show_swe, tiles{end+1} = 'snow'; end
    if show_air || show_tmp, tiles{end+1} = 'temp'; end
    if show_wind,            tiles{end+1} = 'wind'; end

    % Shading spans from the FULL weather table (the centered accumulation
    % window stays valid at the range edges), clipped to the range.
    spans_wet = NaT(0, 2);  spans_cold = NaT(0, 2);
    if want_wet || want_cold
        [wet, cold] = V.U.snowfall_mask(tcol(WX), WX.airtc_c, ...
            col_or_nan(WX, 'swe_mm'), col_or_nan(WX, 'depth_m'));
        spans_wet  = clip_spans(V.U.freeze_spans(tcol(WX), wet),  t0, t1);
        spans_cold = clip_spans(V.U.freeze_spans(tcol(WX), cold), t0, t1);
    end
    c_wet  = [0.00 0.45 0.74];
    c_cold = [0.49 0.18 0.56];

    %% Top panel: within-run circular std
    tl = tiledlayout(S.panel, 2 + numel(tiles), 1, 'TileSpacing', 'compact');
    ax = nexttile(tl, [2 1]);
    hold(ax, 'on');
    [lh, leg] = shade(ax, want_wet, want_cold);
    mk = {'o', 's', '^'};
    hh = gobjects(numel(cols), 1);
    for ii = 1:numel(cols)
        sd_run = splitapply(@(x) M.second_out(M.circ_stats, x), T.(cols{ii}), grp);
        if color_on
            hh(ii) = scatter(ax, t_run(keep), sd_run(keep), 16, cval(keep), ...
                             'filled', 'Marker', mk{ii});
        else
            hh(ii) = plot(ax, t_run(keep), sd_run(keep), '.', ...
                          'Color', domain_color(labs{ii}));
        end
    end
    hold(ax, 'off');
    % Pt x sidebar spinner scales the run points (Line x is disabled for
    % this view); x1 leaves MATLAB's default marker size unchanged.
    F = V.U.style_factors(S.sp_linew.Value, S.sp_ptsz.Value);
    if color_on
        V.U.style_apply(F, gobjects(0), gobjects(0), hh);
        cb = colorbar(ax);
        cb.Layout.Tile = 'east';   % layout-level: keeps all panels x-aligned
        if hour_on
            colormap(ax, hsv(24));   % cyclic map for the cyclic hour
            clim(ax, [0 24]);
            cb.Ticks = (0:4:20) + 0.5;   % bin centers — there is no hour 24
            cb.TickLabels = compose('%d', 0:4:20);
            cb.Label.String = 'Run start hour (capture clock)';
        else
            colormap(ax, parula);
            s_fin = cval(keep & isfinite(cval));
            lo = snr_cut;
            if ~snr_ok, lo = min(s_fin); end
            hi = max(s_fin);
            if isempty(hi) || hi <= lo, hi = lo + 1; end
            clim(ax, [lo hi]);
            cb.Label.String = 'Median run SNR [dB]';
        end
    else
        V.U.style_apply(F, gobjects(0), hh, gobjects(0));
    end
    if numel(cols) > 1 || ~isempty(lh)
        legend(ax, [hh(:); lh(:)], [labs(:); leg(:)], 'Location', 'best');
    end
    ylabel(ax, 'Within-run phase spread (deg)');   % circular std of the run's captures
    title(ax, ['Within-run phase scatter (15 captures / 2-hourly run)' domain_suffix()]);
    grid(ax, 'on');
    axs = ax;
    wl = gobjects(0);   % weather lines, scaled by Line x

    %% Weather panels (15-min station record)
    for k = 1:numel(tiles)
        axw = nexttile(tl);
        hold(axw, 'on');
        shade(axw, want_wet, want_cold);
        switch tiles{k}
            case 'snow'
                if show_dep && show_swe, yyaxis(axw, 'left'); end
                if show_dep
                    R = V.U.wx_axis_cfg('depth', TW.depth_m);
                    wl(end+1) = plot(axw, tcol(TW), TW.depth_m, '-', 'Color', R.color); %#ok<AGROW>
                    ylabel(axw, R.label);
                    axw.YColor = R.color;
                end
                if show_dep && show_swe, yyaxis(axw, 'right'); end
                if show_swe
                    R = V.U.wx_axis_cfg('swe', TW.swe_mm);
                    wl(end+1) = plot(axw, tcol(TW), TW.swe_mm, '-', 'Color', R.color); %#ok<AGROW>
                    ylabel(axw, R.label);
                    if show_dep, axw.YAxis(2).Color = R.color; else, axw.YColor = R.color; end
                end
            case 'temp'
                wxlab = V.U.wx_temp_labels(V.cfg);
                esc = @(s) strrep(s, '_', '\_');
                ht = gobjects(0);  lt = {};
                if show_air
                    ht(end+1) = plot(axw, tcol(TW), TW.airtc_c, '-', 'Color', [0.17 0.63 0.17]); %#ok<AGROW>
                    lt{end+1} = esc(wxlab{1}); %#ok<AGROW>
                end
                if show_tmp
                    ht(end+1) = plot(axw, tcol(TW), TW.temp_c, '-', 'Color', [0.49 0.18 0.56]); %#ok<AGROW>
                    lt{end+1} = esc(wxlab{2}); %#ok<AGROW>
                end
                wl = [wl, ht]; %#ok<AGROW>
                yline(axw, 0, 'k--');   % 0 degC melt-freeze threshold
                ylabel(axw, ['Temp (' char(176) 'C)']);
                legend(axw, ht, lt, 'Location', 'best');
            case 'wind'
                wl(end+1) = plot(axw, tcol(TW), TW.wind_ms, '-', 'Color', [0.30 0.30 0.30]); %#ok<AGROW>
                ylabel(axw, 'Wind (m/s)');
        end
        hold(axw, 'off');
        grid(axw, 'on');
        axs(end+1) = axw; %#ok<AGROW>
    end
    V.U.style_apply(F, wl, gobjects(0), gobjects(0));
    set(axs(1:end-1), 'XTickLabel', {});   % dates on the bottom panel only
    linkaxes(axs, 'x');
    if t1 > t0, xlim(ax, [t0 t1]); end

    function [lh_s, leg_s] = shade(a, on_wet, on_cold)
        % Wet / cold snowfall spans behind the data on axes a.
        lh_s = gobjects(0);  leg_s = {};
        if on_wet && ~isempty(spans_wet)
            hr = xregion(a, spans_wet(:, 1), spans_wet(:, 2), 'FaceColor', c_wet, ...
                         'FaceAlpha', 0.15, 'Layer', 'bottom');
            lh_s(end+1) = hr(1);
            leg_s{end+1} = sprintf('Wet snowfall (|AirTC| %s %g%sC)', char(8804), ...
                                   C.SNOWFALL_WET_ABS_C, char(176));
        end
        if on_cold && ~isempty(spans_cold)
            hr = xregion(a, spans_cold(:, 1), spans_cold(:, 2), 'FaceColor', c_cold, ...
                         'FaceAlpha', 0.12, 'Layer', 'bottom');
            lh_s(end+1) = hr(1);
            leg_s{end+1} = sprintf('Cold snowfall (AirTC < -%g%sC)', ...
                                   C.SNOWFALL_WET_ABS_C, char(176));
        end
    end
end


function y = col_or_nan(T, c)
% Column c of table T, or an all-NaN column when absent.
    if ismember(c, T.Properties.VariableNames)
        y = T.(c);
    else
        y = nan(height(T), 1);
    end
end


function sp = clip_spans(sp, t0, t1)
% [start end] datetime spans clipped to [t0, t1]; spans outside dropped.
    sp = sp(sp(:, 2) > t0 & sp(:, 1) < t1, :);
    sp(:, 1) = max(sp(:, 1), t0);
    sp(:, 2) = min(sp(:, 2), t1);
end
