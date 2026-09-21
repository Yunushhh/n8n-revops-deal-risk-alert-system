-- RevOps Deal Risk Assessment & Alert System
-- SYNTHETIC DEMO DATA. Hand-written for this portfolio project.
--
-- No real people, companies, customers, deals or CRM records appear here. Every
-- deal name is prefixed "Test Deal -" so it cannot be mistaken for a real one.
-- Deal IDs use the shape of HubSpot IDs (numeric strings) so the rows behave
-- like real ones, but they are invented and correspond to nothing.
--
-- This file is the PostgreSQL half of the demonstration. The HubSpot half is
-- examples/pin-data-hubspot-deals.json, pinned onto the "Get Open Deals from
-- HubSpot" node, which lets the workflow run end to end with no HubSpot portal.
-- The two files are matched: the close dates below are identical to the close
-- dates in the pin data, so the first run records no phantom close-date push.
--
-- Load order:
--   1. database/schema.sql
--   2. this file
--   3. pin the JSON onto the HubSpot node, then execute the workflow
--
-- Close dates are fixed literals because they must match the pin data exactly.
-- Everything else is relative to now(), so the scenarios stay meaningful
-- whenever you load them.

BEGIN;

-- ---------------------------------------------------------------------------
-- deal_tracking - close-date history
--
-- Two deals in the pin data are deliberately absent here: 31882010493 and
-- 31882010502 have never been seen before, so the workflow creates their rows
-- on the first run with a push count of zero. That is the first-sighting path,
-- and 31882010493 has no close date at all, which is how a NULL close_date
-- reaches the table.
-- ---------------------------------------------------------------------------
INSERT INTO deal_tracking (deal_id, close_date, close_date_push_count, last_changed_at) VALUES

    -- Closing in 5 days, never pushed. Paired with 45 days of inactivity in the
    -- CRM this triggers NEAR_CLOSE_EXECUTION_GAP and lands the deal at CRITICAL.
    ('31882004417', TIMESTAMPTZ '2026-09-26T00:00:00.000Z', 0, now() - INTERVAL  '31 days'),

    -- Clean record, comfortably out. Contributes no close-date risk at all, so
    -- this deal's score comes purely from buyer coverage and momentum.
    ('31882004612', TIMESTAMPTZ '2026-10-13T00:00:00.000Z', 0, now() - INTERVAL  '18 days'),

    -- Pushed out once: CLOSE_DATE_PUSHED, 10 points, LOW. This is the deal that
    -- recovers and is closed out as RISK_IMPROVED.
    ('31881996204', TIMESTAMPTZ '2026-10-31T00:00:00.000Z', 1, now() - INTERVAL  '12 days'),

    -- Pushed twice and now overdue. Combined with a single contact and a
    -- 250,000 value this is the highest-scoring deal in the set, and the only
    -- one whose three displayed risk drivers are all revenue risk rather than
    -- CRM hygiene.
    ('31882010455', TIMESTAMPTZ '2026-09-10T00:00:00.000Z', 2, now() - INTERVAL   '9 days'),

    -- Steady-state at-risk deal. Its stored alert state below matches exactly
    -- what today's scan computes, which is what routes it to REFRESH.
    ('31882010461', TIMESTAMPTZ '2026-11-20T00:00:00.000Z', 0, now() - INTERVAL   '6 days'),

    ('31882010470', TIMESTAMPTZ '2026-10-24T00:00:00.000Z', 0, now() - INTERVAL  '21 days'),
    ('31882010488', TIMESTAMPTZ '2026-11-08T00:00:00.000Z', 0, now() - INTERVAL  '26 days'),
    ('31882010517', TIMESTAMPTZ '2026-09-01T00:00:00.000Z', 0, now() - INTERVAL  '44 days'),

    -- Pushed three times: CLOSE_DATE_REPEATEDLY_PUSHED. A deal that has slipped
    -- across three forecast periods is never overdue on any single day, which is
    -- exactly why the push count is stored rather than recomputed.
    ('31882010524', TIMESTAMPTZ '2026-10-09T00:00:00.000Z', 3, now() - INTERVAL  '15 days'),

    -- Left the pipeline months ago. The row is kept on purpose: deal_tracking is
    -- only ever read for deals in the current scan, so if this deal reopens its
    -- push history is still correct.
    ('31881990877', TIMESTAMPTZ '2026-06-18T00:00:00.000Z', 2, now() - INTERVAL '120 days')

ON CONFLICT (deal_id) DO NOTHING;


-- ---------------------------------------------------------------------------
-- deal_alert_state - what was last alerted
--
-- Four rows, chosen so that one run exercises all four decision routes:
--
--   31882004417  re-alerts   level moved HIGH -> CRITICAL
--   31882010461  refreshes   level, fingerprint and score all unchanged
--   31881996204  resolves    dropped below the alerting threshold
--   31881990877  is reaped   absent from the scan, last seen 90 days ago
--
-- Every other deal in the pin data is absent from this table on purpose. A deal
-- with no previous state is tagged NEW_RISK_ALERT with trend NEW.
-- ---------------------------------------------------------------------------
INSERT INTO deal_alert_state
    (deal_id, deal_name, risk_level, risk_score, issue_fingerprint,
     first_alerted_at, last_alerted_at, last_seen_at) VALUES

    -- Alerted yesterday at HIGH 40 (STALLED_DEAL 35 + MISSING_NEXT_STEP 10 x 0.5).
    -- Today the close date is inside 7 days, so NEAR_CLOSE_EXECUTION_GAP adds 20
    -- and the deal reaches 60. The level moves HIGH -> CRITICAL, so it re-alerts
    -- with reason RISK_LEVEL_CHANGED, trend RISING, 14 days at risk.
    ('31882004417', 'Test Deal - Logistics Platform Expansion', 'HIGH', 40,
     'MISSING_NEXT_STEP,STALLED_DEAL',
     now() - INTERVAL  '14 days', now() - INTERVAL  '1 day',  now() - INTERVAL  '1 day'),

    -- Alerted six days ago at HIGH 40 with the same two issues it still has
    -- today. Nothing has moved: same level, same fingerprint, score delta zero.
    -- This is the quiet path. last_seen_at is touched, the action-queue row is
    -- refreshed, and no Slack message is sent. It is the single most important
    -- behaviour in the workflow and the hardest to show in a screenshot, which
    -- is why it has a deal of its own.
    ('31882010461', 'Test Deal - Regional Rollout Phase 2', 'HIGH', 40,
     'MISSING_NEXT_STEP,STALLED_DEAL',
     now() - INTERVAL   '6 days', now() - INTERVAL  '1 day',  now() - INTERVAL  '1 day'),

    -- Alerted at HIGH 43 (SINGLE_THREADED 25 + LOSING_MOMENTUM 18). A second
    -- contact has since been added and activity has resumed, so today it scores
    -- 10 (the single close-date push only), drops to LOW, and is routed RESOLVED
    -- with resolution_reason RISK_IMPROVED after 9 days at risk.
    ('31881996204', 'Test Deal - Retail Renewal FY26', 'HIGH', 43,
     'LOSING_MOMENTUM,SINGLE_THREADED',
     now() - INTERVAL   '9 days', now() - INTERVAL  '2 days', now() - INTERVAL  '2 days'),

    -- Stale on purpose. Last seen 90 days ago, well past the 30-day guard, so
    -- because this deal is absent from the scan it is eligible for the
    -- pipeline-exit cleanup and is closed out as NOT_IN_PIPELINE. days_at_risk
    -- is measured from first_alerted_at to last_alerted_at, giving 31.
    --
    -- One orphan against four state rows is inside the reaper's cap of
    -- max(3, ceil(4 * 0.25)) = 3. Add a fifth orphan and the reaper refuses to
    -- run, which is the safeguard working rather than failing.
    ('31881990877', 'Test Deal - Manufacturing Line Upgrade', 'CRITICAL', 70,
     'SEVERELY_STALLED_DEAL,SINGLE_THREADED',
     now() - INTERVAL '121 days', now() - INTERVAL '90 days', now() - INTERVAL '90 days')

ON CONFLICT (deal_id) DO NOTHING;

COMMIT;


-- ---------------------------------------------------------------------------
-- Expected result of the first run
--
--   deal_id      deal                                score  level     route
--   31882010455  Enterprise Infrastructure Renewal      85  CRITICAL  NEEDS_AI (new)
--   31882010517  Public Sector Framework                75  CRITICAL  NEEDS_AI (new)
--   31882004417  Logistics Platform Expansion           60  CRITICAL  NEEDS_AI (level changed)
--   31882010524  Partner Co-Sell Expansion              53  HIGH      NEEDS_AI (new)
--   31882004612  Health Analytics Module                43  HIGH      NEEDS_AI (new)
--   31882010461  Regional Rollout Phase 2               40  HIGH      REFRESH
--   31882010493  Hygiene Gap Pilot                      33  MODERATE  NOOP
--   31882010470  Midmarket CRM Migration                23  MODERATE  NOOP
--   31881996204  Retail Renewal FY26                    10  LOW       RESOLVED
--   31882010488  Support Tier Upgrade                    0  LOW       NOOP
--   31882010502  Startup Pilot Programme                 0  LOW       NOOP
--   31881990877  Manufacturing Line Upgrade              -  -         reaped
--
-- Daily summary row: scanned 11, low 3, moderate 2, high 3, critical 3,
-- high_value_at_risk 1, single_threaded 2, data_quality_only 0,
-- missing_close_date 1, exposure 598,000.
--
-- data_quality_only reads 0 because hygiene alone cannot reach an alerting
-- level. "Hygiene Gap Pilot" is the proof: it is missing an amount, an owner, a
-- next step, a close date and any associated contact, which is 65 raw hygiene
-- points, and it still only reaches 33 - seven points short of HIGH.
--
--
-- Resetting between runs
--
-- The workflow is stateful, so a second run against the same state produces a
-- quiet day rather than the picture above. To reproduce the first run:
--
--   TRUNCATE deal_tracking, deal_alert_state;
--
-- then load this file again and clear the five Google Sheets tabs.
--
-- A note on dates
--
-- The pinned HubSpot data uses fixed timestamps, so the day counts it produces
-- shift by one per day: a deal that is 45 days inactive today reads 46 tomorrow.
-- Every deal sits comfortably inside its scoring band, so the levels and routes
-- above hold for roughly two weeks. The one exception is Logistics Platform
-- Expansion, which closes in five days: once that date passes it stops scoring
-- NEAR_CLOSE_EXECUTION_GAP and starts scoring EXPIRED_CLOSE_DATE instead.
--
-- To refresh the set, shift every date in examples/pin-data-hubspot-deals.json
-- and every close_date literal above forward by the same number of days.
-- ---------------------------------------------------------------------------
