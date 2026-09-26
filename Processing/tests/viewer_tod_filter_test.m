function tests = viewer_tod_filter_test
% Unit tests for the L2: Candidates daily time-of-day filter helpers in
% soop_viewer_util: parse_tod (input grammar), tod_daily_idx
% (target-centered one-capture-per-day selection), tod_run_idx (one run per
% day for the daily filter) and circ_median_grp (per-group circular median).
% Run: matlab -batch "soop_setup_paths; addpath('tests'); runtests('viewer_tod_filter_test')"
    tests = functiontests(localfunctions);
end


function setupOnce(tc)
    tc.TestData.U = soop_viewer_util();
end


% ---------------------------------------------------------------- parse_tod

function test_parse_accepts(tc)
    % Grammar: H, HH, HMM, HHMM, H:MM, HH:MM (hour 0-23, minute 0-59).
    U = tc.TestData.U;
    cases = {'0600', hours(6);        '06:00', hours(6)
             '6',    hours(6);        '600',   hours(6)
             '6:30', hours(6.5);      '23:59', hours(23) + minutes(59)
             '2359', hours(23) + minutes(59)
             '0',    hours(0);        '00:00', hours(0)
             '23',   hours(23);       '  0600  ', hours(6)};
    for k = 1:size(cases, 1)
        [dur, ok] = U.parse_tod(cases{k, 1});
        verifyTrue(tc, ok, sprintf('should accept %s', strtrim(cases{k, 1})));
        verifyEqual(tc, dur, cases{k, 2}, ...
            sprintf('wrong duration for %s', strtrim(cases{k, 1})));
    end
end

function test_parse_rejects(tc)
    % Out-of-range fields, malformed separators, signs/decimals, junk.
    U = tc.TestData.U;
    bad = {'', '24:00', '2400', '24', '0660', '23:60', '060', 'abc', ...
           '6.5', '-600', '+0600', '06:0', '06:000', '123456', '6 00', ...
           '6:', ':30', '0600x'};
    for k = 1:numel(bad)
        [~, ok] = U.parse_tod(bad{k});
        verifyFalse(tc, ok, sprintf('should reject "%s"', bad{k}));
    end
end


% ------------------------------------------------------------ tod_daily_idx

function test_nearest_per_day(tc)
    % Day 1 has 05:30 and 06:10 (06:10 wins: 10 min beats 30 min); day 2's
    % only capture is 18:00 (dropped, outside the window); day 3's single
    % 06:59 capture is kept (59 min).
    U = tc.TestData.U;
    t = datetime(2026, 1, [1 1 2 3]') + [hours(5) + minutes(30);
                                         hours(6) + minutes(10);
                                         hours(18);
                                         hours(6) + minutes(59)];
    [idx, tday] = U.tod_daily_idx(t, hours(6), hours(1));
    verifyEqual(tc, idx, [2; 4]);
    verifyEqual(tc, tday, datetime(2026, 1, [1; 3]));
end

function test_window_boundary(tc)
    % Exactly 1 h away is kept (<=); one minute past is dropped.
    U = tc.TestData.U;
    t = datetime(2026, 1, [1 2]') + [hours(7); hours(7) + minutes(1)];
    [idx, tday] = U.tod_daily_idx(t, hours(6), hours(1));
    verifyEqual(tc, idx, 1);
    verifyEqual(tc, tday, datetime(2026, 1, 1));
end

function test_cross_midnight(tc)
    % Target 23:30. Jan 2 00:15 is nearest to *Jan 1's* target instant
    % (45 min) and Jan 2 23:20 to Jan 2's (10 min): two captures sharing a
    % calendar date serve two different target days. Calendar-date grouping
    % would lose the Jan 1 point.
    U = tc.TestData.U;
    t = [datetime(2026, 1, 2) + hours(0) + minutes(15);
         datetime(2026, 1, 2) + hours(23) + minutes(20)];
    tgt = hours(23) + minutes(30);
    [idx, tday] = U.tod_daily_idx(t, tgt, hours(1));
    verifyEqual(tc, idx, [1; 2]);
    verifyEqual(tc, tday, datetime(2026, 1, [1; 2]));
end

function test_tie_keeps_first_row(tc)
    % 06:10 and 05:50 are both 10 min from 06:00; the earlier *row* (input
    % order, not clock order) wins deterministically.
    U = tc.TestData.U;
    t = datetime(2026, 1, 1) + [hours(6) + minutes(10);
                                hours(5) + minutes(50)];
    idx = U.tod_daily_idx(t, hours(6), hours(1));
    verifyEqual(tc, idx, 1);
end

function test_unsorted_input(tc)
    % Shuffled input: indices come back in original coordinates, ascending.
    U = tc.TestData.U;
    t = [datetime(2026, 1, 3) + hours(6) + minutes(20);   % day 3 winner
         datetime(2026, 1, 1) + hours(6) + minutes(5);    % day 1 winner
         datetime(2026, 1, 3) + hours(6) + minutes(40);
         datetime(2026, 1, 1) + hours(7) + minutes(30)];
    [idx, tday] = U.tod_daily_idx(t, hours(6), hours(1));
    verifyEqual(tc, idx, [1; 2]);
    verifyEqual(tc, tday, datetime(2026, 1, [3; 1]));   % aligned with idx
end

function test_duplicate_timestamps(tc)
    % Identical stamps: first original row wins.
    U = tc.TestData.U;
    t = datetime(2026, 1, 1) + hours(6) + [minutes(10); minutes(10)];
    idx = U.tod_daily_idx(t, hours(6), hours(1));
    verifyEqual(tc, idx, 1);
end

function test_nat_and_empty(tc)
    % Empty and all-NaT inputs return empty; mixed NaT rows are ignored.
    U = tc.TestData.U;
    [idx, tday] = U.tod_daily_idx(datetime.empty(0, 1), hours(6), hours(1));
    verifyEmpty(tc, idx);
    verifyEmpty(tc, tday);
    idx = U.tod_daily_idx(NaT(3, 1), hours(6), hours(1));
    verifyEmpty(tc, idx);
    t = [NaT; datetime(2026, 1, 1) + hours(6); NaT];
    idx = U.tod_daily_idx(t, hours(6), hours(1));
    verifyEqual(tc, idx, 2);
end

function test_zoned_input_rejected(tc)
    % Contract: naive wall-clock datetimes only (timeofday/dateshift diverge
    % from the displayed clock across DST for zoned datetimes).
    U = tc.TestData.U;
    t = datetime(2026, 1, 1, 6, 0, 0, 'TimeZone', 'America/Boise');
    verifyError(tc, @() U.tod_daily_idx(t, hours(6), hours(1)), ...
                'soop_viewer_util:tod_daily_idx:zoned');
end

function test_two_hourly_schedule_always_kept(tc)
    % The Brundage schedule captures every 2 h, so any target instant on a
    % fully covered day is at most 1 h from a capture — with the inclusive
    % boundary the day keeps exactly one row, whatever the target. (Two
    % days of data so late targets can bind day 1's just-past-midnight
    % neighbor, per the target-centered assignment.)
    U = tc.TestData.U;
    day = datetime(2026, 1, 1);
    t = day + hours(0:2:46)';   % Jan 1 00:00 .. Jan 2 22:00, every 2 h
    for tgt = [hours(0), hours(6), hours(7), hours(13), hours(23) + minutes(59)]
        [~, tday] = U.tod_daily_idx(t, tgt, hours(1));
        verifyEqual(tc, sum(tday == day), 1, ...
            sprintf('target %s should keep one row for day 1', char(tgt, 'hh:mm')));
    end
end


% -------------------------------------------------------------- tod_run_idx

function [t, g] = two_day_runs()
% Day 1: a 5-capture run at 06:00 and a 3-capture run at 08:00 (outside
% +-1 h of a 06:00 target). Day 2: a 3-capture run at 05:30. Captures within a
% run are 10 s apart; labels are gapped (x7) as carried run ids can be.
    d = datetime(2026, 1, 10);
    t = [d + hours(6) + seconds(0:10:40)';
         d + hours(8) + seconds(0:10:20)';
         d + days(1) + hours(5.5) + seconds(0:10:20)'];
    g = 7 * [1; 1; 1; 1; 1; 2; 2; 2; 3; 3; 3];
end

function test_run_idx_returns_all_members(tc)
    % Each day returns every member of the run holding its nearest capture,
    % with the day aligned to each member; the 08:00 run is out of window.
    U = tc.TestData.U;
    [t, g] = two_day_runs();
    [ix, tday] = U.tod_run_idx(t, g, hours(6), hours(1), 1);
    verifyEqual(tc, ix, [1; 2; 3; 4; 5; 9; 10; 11]);
    verifyEqual(tc, tday, [repmat(datetime(2026, 1, 10), 5, 1); ...
                           repmat(datetime(2026, 1, 11), 3, 1)]);
end

function test_run_idx_min_n_drops_thin_run(tc)
    % Day 2's run keeps 3 contributors: below min_n = 4 it cannot serve.
    U = tc.TestData.U;
    [t, g] = two_day_runs();
    [ix, tday] = U.tod_run_idx(t, g, hours(6), hours(1), 4);
    verifyEqual(tc, ix, (1:5)');
    verifyEqual(tc, unique(tday), datetime(2026, 1, 10));
end

function test_run_idx_min_n_falls_to_other_run(tc)
    % A target at 07:00 is equidistant-ish between runs; with the 06:00 run
    % too thin the day falls to the eligible 08:00 run inside the window.
    U = tc.TestData.U;
    d = datetime(2026, 1, 10);
    t = [d + hours(6.5) + seconds(0:10:10)';     % 2 captures, nearest
         d + hours(7.75) + seconds(0:10:30)'];   % 4 captures, 45 min away
    g = [1; 1; 2; 2; 2; 2];
    [ix, ~] = U.tod_run_idx(t, g, hours(7), hours(1), 3);
    verifyEqual(tc, ix, (3:6)');
    [ix, ~] = U.tod_run_idx(t, g, hours(7), hours(1), 1);
    verifyEqual(tc, ix, [1; 2], 'nearest run wins when both are eligible');
end

function test_run_idx_members_outside_window(tc)
    % A run whose nearest capture is inside +-1 h returns ALL members, even
    % those past the window edge.
    U = tc.TestData.U;
    d = datetime(2026, 1, 10);
    t = d + hours(6) + minutes([55; 58; 61; 64]);
    [ix, ~] = U.tod_run_idx(t, ones(4, 1), hours(6), hours(1), 1);
    verifyEqual(tc, ix, (1:4)');
end

function test_run_idx_near_midnight_target(tc)
    % Target 23:30: a run straddling midnight binds to the target-centered
    % day, not the calendar date of its later members.
    U = tc.TestData.U;
    d = datetime(2026, 1, 10);
    t = d + hours(23) + minutes([50; 55; 60; 65]);
    [ix, tday] = U.tod_run_idx(t, ones(4, 1), hours(23.5), hours(1), 1);
    verifyEqual(tc, ix, (1:4)');
    verifyEqual(tc, unique(tday), d);
end

function test_run_idx_run_owned_by_one_day(tc)
    % A chained run (20-min spacing, never a > 30 min gap) spans two 06:00
    % targets. Nearest distances: day 1 10 min, day 2 2 min (extra capture at
    % 06:02) -> day 2 owns the run and day 1 drops. Without the extra capture
    % both are 10 min -> the earliest day owns it.
    U = tc.TestData.U;
    d = datetime(2026, 1, 10);
    t = d + hours(5) + minutes(10) + minutes(0:20:1500)';   % 05:10 .. +1 d 06:10
    t2 = sort([t; d + days(1) + hours(6) + minutes(2)]);
    [ix, tday] = U.tod_run_idx(t2, ones(numel(t2), 1), hours(6), hours(1), 1);
    verifyEqual(tc, ix, (1:numel(t2))', 'all members returned');
    verifyEqual(tc, unique(tday), d + days(1));
    [~, tday] = U.tod_run_idx(t, ones(numel(t), 1), hours(6), hours(1), 1);
    verifyEqual(tc, unique(tday), d, 'distance tie -> earliest day');
end

function test_run_idx_gapped_labels_and_removed_middle_run(tc)
    % Filtering removes an entire middle run: remaining labels are
    % non-consecutive, and selection still counts per run correctly.
    U = tc.TestData.U;
    [t, g] = two_day_runs();
    keep = g ~= 14;                      % drop the whole 08:00 run
    [ix, ~] = U.tod_run_idx(t(keep), g(keep), hours(6), hours(1), 3);
    verifyEqual(tc, ix, (1:8)');
end

function test_run_idx_nat_unsorted_empty(tc)
    % NaT rows are ignored, unsorted input returns ascending original
    % indices, empty input returns empty outputs.
    U = tc.TestData.U;
    [t, g] = two_day_runs();
    p = [11; 3; 9; 1; 5; 2; 4; 10; 6; 7; 8];
    [ix, ~] = U.tod_run_idx(t(p), g(p), hours(6), hours(1), 1);
    verifyEqual(tc, sort(p(ix)), [1; 2; 3; 4; 5; 9; 10; 11]);
    verifyTrue(tc, issorted(ix));
    t2 = t;  t2(2) = NaT;
    [ix, ~] = U.tod_run_idx(t2, g, hours(6), hours(1), 1);
    verifyFalse(tc, ismember(2, ix));
    [ix, tday] = U.tod_run_idx(datetime.empty(0, 1), zeros(0, 1), ...
                               hours(6), hours(1), 1);
    verifyEmpty(tc, ix);  verifyEmpty(tc, tday);
end

function test_run_idx_validation(tc)
    % Programmer-error inputs raise identified errors.
    U = tc.TestData.U;
    [t, g] = two_day_runs();
    verifyError(tc, @() U.tod_run_idx(t, g(1:3), hours(6), hours(1), 1), ...
                'soop_viewer_util:tod_run_idx:length');
    for bad = {0, 2.5, -1, [1 2], NaN, '3'}
        verifyError(tc, @() U.tod_run_idx(t, g, hours(6), hours(1), bad{1}), ...
                    'soop_viewer_util:tod_run_idx:min_n');
    end
    tz = datetime(2026, 1, 10, 6, 0, 0, 'TimeZone', 'America/Boise');
    verifyError(tc, @() U.tod_run_idx(tz, 1, hours(6), hours(1), 1), ...
                'soop_viewer_util:tod_run_idx:zoned');
end


% ---------------------------------------------------------- circ_median_grp

function test_circ_median_wrap_cluster(tc)
    % A cluster straddling +-180 gives the median on the short arc.
    U = tc.TestData.U;
    [med, n] = U.circ_median_grp([179; -179; 178], [1; 1; 1]);
    verifyEqual(tc, med, 179, 'AbsTol', 1e-9);
    verifyEqual(tc, n, 3);
end

function test_circ_median_dispersed_is_l1_minimizer(tc)
    % Dispersed samples: the result minimizes the summed arc distance (a
    % mean-centered median gives 17.85 deg, cost 305.7, here).
    U = tc.TestData.U;
    y = [60.9; 168.4; -25.2; -51.2];
    med = U.circ_median_grp(y, ones(4, 1));
    verifyEqual(tc, med, -38.2, 'AbsTol', 1e-9);
    cost = @(m) sum(abs(mod(y - m + 180, 360) - 180));
    grid = -180:0.1:179.9;
    verifyLessThanOrEqual(tc, cost(med), min(arrayfun(cost, grid)) + 1e-6);
end

function test_circ_median_even_and_groups(tc)
    % Even count on concentrated data gives the midpoint; groups follow
    % sorted label order; an all-NaN group is NaN with n = 0.
    U = tc.TestData.U;
    [med, n] = U.circ_median_grp([10; 12; 14; 20; NaN; NaN; -30], ...
                                 [5; 5; 5; 5; 5; 9; 2]);
    verifyEqual(tc, med, [-30; 13; NaN], 'AbsTol', 1e-9);
    verifyEqual(tc, n, [1; 4; 0]);
end

function test_circ_median_antipodal_deterministic(tc)
    % An antipodal pair has a tied cost everywhere on the two arcs: the
    % result is deterministic and cost-minimal.
    U = tc.TestData.U;
    y = [0; 180];
    m1 = U.circ_median_grp(y, [1; 1]);
    m2 = U.circ_median_grp(y, [1; 1]);
    verifyEqual(tc, m1, m2);
    verifyEqual(tc, sum(abs(mod(y - m1 + 180, 360) - 180)), 180, 'AbsTol', 1e-9);
    verifyGreaterThanOrEqual(tc, m1, -180);  verifyLessThan(tc, m1, 180);
end

function test_circ_median_length_check(tc)
    U = tc.TestData.U;
    verifyError(tc, @() U.circ_median_grp([1; 2], 1), ...
                'soop_viewer_util:circ_median_grp:length');
end
