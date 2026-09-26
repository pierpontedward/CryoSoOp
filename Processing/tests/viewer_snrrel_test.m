function tests = viewer_snrrel_test
% Unit tests for the run-relative SNR rejection helpers in soop_viewer_util:
% snrrel_keep (per-run median/max reference), the snrcut_apply row mask, and
% empty_stage_msg (first emptying stage).
% Run: matlab -batch "soop_setup_paths; addpath('tests'); runtests('viewer_snrrel_test')"
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.U = soop_viewer_util();
end


% -------------------------------------------------------------- snrrel_keep

function test_median_reference(tc)
    % Run 3: median of {45, 44, 30, 50} = 44.5 -> keep >= 39.5 (30 drops,
    % NaN drops). Run 8 (singleton 20) keeps its capture.
    U = tc.TestData.U;
    [k, ok] = U.snrrel_keep([45; 44; 30; 50; NaN; 20], [3; 3; 3; 3; 3; 8], 5, 'median');
    verifyTrue(tc, ok);
    verifyEqual(tc, k, logical([1; 1; 0; 1; 0; 1]));
end

function test_max_reference(tc)
    % Run 3: max 50 -> keep >= 45 (44 now drops too).
    U = tc.TestData.U;
    [k, ok] = U.snrrel_keep([45; 44; 30; 50; NaN; 20], [3; 3; 3; 3; 3; 8], 5, "max");
    verifyTrue(tc, ok);
    verifyEqual(tc, k, logical([1; 0; 0; 1; 0; 1]));
end

function test_inclusive_boundary_and_zero_drop(tc)
    % Exactly ref - drop is kept; drop 0 against max keeps only the maxima.
    U = tc.TestData.U;
    k = U.snrrel_keep([40; 45; 45], [1; 1; 1], 5, 'max');
    verifyEqual(tc, k, true(3, 1));
    k = U.snrrel_keep([40; 45; 45], [1; 1; 1], 0, 'max');
    verifyEqual(tc, k, logical([0; 1; 1]));
end

function test_nonfinite_run_keeps_nothing(tc)
    % A run with no finite SNR keeps nothing, for both references.
    U = tc.TestData.U;
    for ref = {'median', 'max'}
        k = U.snrrel_keep([NaN; Inf; -Inf; 30], [1; 1; 1; 2], 5, ref{1});
        verifyEqual(tc, k, logical([0; 0; 0; 1]), ref{1});
    end
end

function test_groups_independent_and_gapped(tc)
    % Interleaved rows, arbitrary labels: each run uses its own reference.
    U = tc.TestData.U;
    snr = [50; 20; 44; 21; 49; 10];
    grp = [100; 7; 100; 7; 100; 7];
    k = U.snrrel_keep(snr, grp, 5, 'median');
    % run 100 median 49 -> keep >= 44; run 7 median 20 -> keep >= 15.
    verifyEqual(tc, k, logical([1; 1; 1; 1; 1; 0]));
end

function test_fail_safe_inputs(tc)
    % Invalid operator input never filters: keep all-true, ok false.
    U = tc.TestData.U;
    snr = [40; 30];  grp = [1; 1];
    bad = {{snr, grp, -1, 'median'}, {snr, grp, NaN, 'median'}, ...
           {snr, grp, [1 2], 'median'}, {snr, grp, 5, 'mean'}, ...
           {snr, [1; 1; 1], 5, 'median'}, {{'a'; 'b'}, grp, 5, 'median'}, ...
           {snr, grp, 5, ["median" "max"]}, {snr, grp, 5, ["median" "bogus"]}, ...
           {snr, grp, 5, ["bogus" "max"]}, {snr, grp, 5, {'median'}}, ...
           {snr, grp, 5, ['max'; 'max']}, {snr, grp, 5, ""}};
    for b = 1:numel(bad)
        a = bad{b};
        [k, ok] = U.snrrel_keep(a{:});
        verifyFalse(tc, ok, sprintf('case %d', b));
        verifyEqual(tc, k, true(numel(a{1}), 1), sprintf('case %d', b));
    end
end

function test_overflow_excluded_before_reference(tc)
    % The caller computes the reference over post-overflow rows only: a
    % flagged high-SNR capture does not raise the max reference.
    U = tc.TestData.U;
    snr = [60; 45; 42];  grp = [1; 1; 1];
    k_ovf = logical([0; 1; 1]);                       % 60 dB row is flagged
    keep = k_ovf;
    [kr, ok] = U.snrrel_keep(snr(k_ovf), grp(k_ovf), 5, 'max');
    verifyTrue(tc, ok);
    keep(k_ovf) = kr;
    verifyEqual(tc, keep, logical([0; 1; 1]), 'reference 45, not 60');
end

function test_absolute_cutoff_does_not_move_reference(tc)
    % Relative mask is computed before the absolute cutoff: it is the same
    % for any cutoff value, and the combined mask is their intersection.
    U = tc.TestData.U;
    T = table([40; 44; 46; 30], [1; 1; 1; 1], 'VariableNames', {'snr_db', 'g'});
    kr = U.snrrel_keep(T.snr_db, T.g, 5, 'median');      % median 42 -> >= 37
    for cut = [10, 41, 45]
        [~, ok, ks] = U.snrcut_apply(T, cut);
        verifyTrue(tc, ok);
        verifyEqual(tc, U.snrrel_keep(T.snr_db, T.g, 5, 'median'), kr);
        verifyEqual(tc, kr & ks, kr & T.snr_db >= cut, sprintf('cut %g', cut));
    end
end


% ---------------------------------------------------- snrcut_apply row mask

function test_snrcut_mask_output(tc)
    % Third output is the row mask applied; all-true when the cut cannot act.
    U = tc.TestData.U;
    T = table([5; 15; NaN; 20], 'VariableNames', {'snr_db'});
    [Tf, ok, k] = U.snrcut_apply(T, 10);
    verifyTrue(tc, ok);
    verifyEqual(tc, k, logical([0; 1; 0; 1]));
    verifyEqual(tc, Tf, T(k, :));
    [Tf, ok, k] = U.snrcut_apply(T, NaN);
    verifyFalse(tc, ok);
    verifyEqual(tc, k, true(4, 1));
    verifyEqual(tc, Tf, T);
    [~, ok, k] = U.snrcut_apply(table((1:3)', 'VariableNames', {'x'}), 10);
    verifyFalse(tc, ok);
    verifyEqual(tc, k, true(3, 1));
end


% --------------------------------------------------------- empty_stage_msg

function test_empty_stage_first_zero(tc)
    % The first stage whose cumulative count is zero names the cause.
    U = tc.TestData.U;
    msgs = {'window', 'overflow', 'relative', 'cutoff'};
    verifyEqual(tc, U.empty_stage_msg([0 0 0 0], msgs, 'fb'), 'window');
    verifyEqual(tc, U.empty_stage_msg([4 0 0 0], msgs, 'fb'), 'overflow');
    verifyEqual(tc, U.empty_stage_msg([4 3 0 0], msgs, 'fb'), 'relative');
    verifyEqual(tc, U.empty_stage_msg([4 3 2 0], msgs, 'fb'), 'cutoff');
    verifyEqual(tc, U.empty_stage_msg([4 3 2 1], msgs, 'fb'), 'fb');
end
