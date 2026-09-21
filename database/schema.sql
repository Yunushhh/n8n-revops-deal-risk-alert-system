-- RevOps Deal Risk Assessment & Alert System
-- PostgreSQL schema for the two state tables the workflow reads and writes.
--
-- These tables hold workflow memory only. They are not a copy of the CRM:
-- deal fields are read live from HubSpot on every run, and only the values that
-- have to survive between runs are stored here.
--
-- Column names and types match the field mappings in the workflow's Postgres nodes.

-- ---------------------------------------------------------------------------
-- deal_tracking
--   Written by : Save Close Date History  (upsert, matched on deal_id)
--   Read by    : Load Close Date History  (full table select, once per run)
--   Purpose    : remembers the close date last seen for each deal so the next
--                run can tell whether the date moved, and counts how many times
--                it has been pushed outward. A pushed close date is one of the
--                strongest slip signals and is invisible in a single snapshot.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deal_tracking (
    deal_id               TEXT PRIMARY KEY,
    close_date            TIMESTAMPTZ,
    close_date_push_count INTEGER     NOT NULL DEFAULT 0,
    last_changed_at       TIMESTAMPTZ
);

COMMENT ON TABLE  deal_tracking                       IS 'Close-date history per deal; enables push detection across runs.';
COMMENT ON COLUMN deal_tracking.close_date            IS 'Close date observed on the most recent run in which it changed.';
COMMENT ON COLUMN deal_tracking.close_date_push_count IS 'Times the close date has moved outward since the deal was first seen. Pull-ins are recorded but never counted.';
COMMENT ON COLUMN deal_tracking.last_changed_at       IS 'When this row was last written. Rows are only written when the date actually moved.';


-- ---------------------------------------------------------------------------
-- deal_alert_state
--   Written by : Save Alert State        (upsert, after Slack confirms delivery)
--                Mark Deal Still at Risk (update of last_seen_at only)
--   Read by    : Load Previous Alert State (full table select, once per run)
--   Deleted by : Clear Alert State       (delete by deal_id, on resolution)
--   Purpose    : remembers what was last alerted for each deal. This is what
--                makes the workflow quiet: a deal is only alerted again when its
--                risk level, its set of issues, or its score has actually moved.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deal_alert_state (
    deal_id           TEXT PRIMARY KEY,
    deal_name         TEXT,
    risk_level        TEXT,
    risk_score        NUMERIC,
    issue_fingerprint TEXT,
    first_alerted_at  TIMESTAMPTZ,
    last_alerted_at   TIMESTAMPTZ,
    last_seen_at      TIMESTAMPTZ
);

COMMENT ON TABLE  deal_alert_state                   IS 'One row per deal currently in an alerted state. Deleted when the deal resolves.';
COMMENT ON COLUMN deal_alert_state.risk_level        IS 'HIGH or CRITICAL as of the last delivered alert.';
COMMENT ON COLUMN deal_alert_state.risk_score        IS 'Score 0-100 as of the last delivered alert; compared against today to derive the trend.';
COMMENT ON COLUMN deal_alert_state.issue_fingerprint IS 'Sorted, comma-separated issue codes. A change here means a different problem, not the same one.';
COMMENT ON COLUMN deal_alert_state.first_alerted_at  IS 'Start of the current at-risk spell; preserved across re-alerts to compute days at risk.';
COMMENT ON COLUMN deal_alert_state.last_alerted_at   IS 'When an alert was last actually delivered to Slack.';
COMMENT ON COLUMN deal_alert_state.last_seen_at      IS 'When the deal was last present in a scan, alerted or not. Protects steady-state deals from cleanup.';


-- No indexes beyond the primary keys, and no foreign key between the tables.
-- Both are deliberate, not omissions:
--
--   * Every read the workflow performs is either a full-table select (both load
--     nodes) or a lookup by deal_id (upsert, update, delete). The primary key
--     serves all of them. An index on last_seen_at or risk_level would be dead
--     weight: the pipeline-exit cleanup filters those values in JavaScript, not
--     in SQL, so no query would ever use them.
--
--   * The two tables have independent lifecycles. A deal_tracking row is kept
--     after a deal closes, so its push history survives if the deal reopens; a
--     deal_alert_state row is deleted the moment the deal resolves. A foreign
--     key in either direction would block one of those behaviours.
