# Demo Setup

This guide explains how to reproduce the portfolio demonstration locally.
The workflow export contains credential references and placeholders, not
secrets. Use a sandbox HubSpot portal and synthetic records.

## Prerequisites

- n8n
- PostgreSQL
- A HubSpot private app (optional - see section 0)
- A Slack workspace and bot
- Two Google Sheets spreadsheets
- An OpenRouter API key

## 0. Run it without HubSpot (recommended first)

The workflow can be demonstrated end to end with no HubSpot portal.
`examples/pin-data-hubspot-deals.json` contains eleven synthetic deals in the
exact shape the HubSpot Deals search API returns.

1. Open the `Get Open Deals from HubSpot` node.
2. In the OUTPUT panel, click **Edit Output**.
3. Paste the contents of the file and save. A pin badge appears on the node.

Every downstream branch then runs for real against PostgreSQL, Google Sheets and
Slack. The eleven deals exercise all four decision routes plus the pipeline-exit
cleanup in a single execution, and `database/sample-data.sql` supplies the
matching stored state. The close dates in the two files are identical on
purpose, so the first run records no phantom close-date push.

Unpin the node to switch to live HubSpot data.

## 1. Create the PostgreSQL tables

Run the schema file:

```bash
psql "$DATABASE_URL" -f database/schema.sql
```

Optionally load the synthetic state used by the example:

```bash
psql "$DATABASE_URL" -f database/sample-data.sql
```

The database contains `deal_tracking` for close-date history and
`deal_alert_state` for the last delivered alert state.

## 2. Import the n8n workflow

1. Open n8n.
2. Import `workflow/revops-deal-risk-assessment-and-alert-system.json`.
3. Review the imported nodes before enabling the schedule.

## 3. Create credentials

Create credentials in your own n8n instance and select them on the relevant
nodes:

- HubSpot private app token with `crm.objects.deals.read`
- PostgreSQL connection
- Slack bot token with `chat:write`
- Google service account with access to both spreadsheets
- OpenRouter API key

Invite the Slack bot to both the risk and engineering channels.

## 4. Replace placeholders

Replace the environment-specific values in the imported workflow:

| Placeholder | Where | What it is |
|---|---|---|
| `YOUR_HUBSPOT_PORTAL_ID` | `Calculate Deal Risk`, line 13 | Used to build deal record links |
| `YOUR_OPS_SPREADSHEET_ID` | 6 Sheets nodes | Operational spreadsheet |
| `YOUR_AUDIT_SPREADSHEET_ID` | `Log Risk Assessment` | Audit spreadsheet |
| `YOUR_RISK_CHANNEL_ID` | 2 Slack nodes | Business risk channel |
| `YOUR_ERROR_CHANNEL_ID` | 2 Slack nodes | Engineering channel |

Credential references are also placeholdered. Selecting your own credential on
each node replaces them, so there is nothing to edit by hand:

| Placeholder | Where |
|---|---|
| `YOUR_HUBSPOT_CREDENTIAL_ID` | `Get Open Deals from HubSpot` |
| `YOUR_POSTGRES_CREDENTIAL_ID` | 6 Postgres nodes |
| `YOUR_GOOGLE_CREDENTIAL_ID` | 7 Sheets nodes |
| `YOUR_SLACK_CREDENTIAL_ID` | 4 Slack nodes |
| `YOUR_OPENROUTER_CREDENTIAL_ID` | `AI Model - Gemini Flash Lite` |

`YOUR_WORKFLOW_ID` and `YOUR_N8N_INSTANCE_ID` are the export's own identifiers.
n8n assigns new ones on import and neither needs to be edited.

### Reporting timezone

The Google Sheets nodes format timestamps with
`DateTime.fromISO(...).setZone('Asia/Kolkata')`. This appears in nine field
mappings across the seven Sheets nodes. Replace `Asia/Kolkata` with your own
IANA timezone, or the logs will be written in Indian Standard Time.

The daily trigger fires at 08:00 in the timezone set on the workflow itself
(`settings.timezone`, currently `Asia/Kolkata`). Change it in n8n under
Workflow settings → Timezone, or edit the exported JSON directly. This is
separate from the nine `setZone('Asia/Kolkata')` calls above, which control
how timestamps are written to Google Sheets rather than when the scan runs.

Do not commit real credentials, tokens, spreadsheet IDs or private portal
details to the repository.

## 5. Create the Google Sheets tabs

Create an operational spreadsheet containing:

- `Risk Scan Summary`
- `RevOps Action Queue`
- `Alert Log`
- `Resolved Log`

Create a separate spreadsheet containing:

- `Deal Risk Assessment`

The audit log is separated because it grows by one row per deal per day.
Column headers must match the field mappings configured on the Sheets nodes.

### Column headers

The Google Sheets node matches on header **name**, not position, so the order
below is a suggestion but the spelling is not. Paste each row into row 1 of
its tab.

**Risk Scan Summary**
```
run_timestamp	execution_id	deals_scanned	low_risk_count	moderate_risk_count	high_risk_count	critical_risk_count	high_value_risk_count	single_threaded_count	data_quality_only_count	missing_close_date_count	total_exposure_high_critical
```

**RevOps Action Queue**
```
last_evaluated_at	deal_id	deal_name	deal_url	owner_id	amount	stage	days_to_close	inactive_days	contact_count	risk_level	risk_score	risk_trend	risk_drivers	alert_reason	days_at_risk	action_status	recommended_action
```

**Alert Log**
```
alerted_at	deal_id	deal_name	owner_id	risk_level	risk_score	alert_reason	issue_fingerprint	action_source	slack_channel	execution_id
```

**Resolved Log**
```
resolved_at	deal_id	deal_name	owner_id	resolution_reason	last_risk_level	last_risk_score	last_issue_codes	new_risk_level	new_risk_score	days_at_risk	resolved_execution_id
```

**Deal Risk Assessment** (audit spreadsheet)
```
timestamp	deal_id	deal_name	owner_id	amount	amount_home	currency	stage	pipeline	close_date	close_date_push_count	last_activity_at	activity_source	age_days	inactive_days	days_to_close	contact_count	risk_score	previous_risk_score	risk_level	deal_risk_score	data_quality_score	issue_codes	issue_fingerprint	risk_drivers	score_breakdown	execution_id
```

Format every timestamp column as **plain text** (Format → Number → Plain
text). The workflow writes `yyyy-MM-dd HH:mm:ss`; left on automatic, Sheets
parses some of those cells into locale dates and leaves others as strings, so
the same value renders differently across tabs.

## 6. Run the demonstration safely

1. Start with a sandbox HubSpot portal containing synthetic deals.
2. Run the workflow manually while the schedule is disabled.
3. Confirm that summary, audit, queue and resolution rows are written.
4. Confirm that Slack messages appear in the intended channels.
5. Inspect PostgreSQL state before enabling the daily schedule.

The first run may generate alerts for all qualifying synthetic deals. This is
expected for a fresh state store.

### Reproducing the workflow error alert

Rename a column the state write depends on, run once, then restore it:

    ALTER TABLE deal_alert_state RENAME COLUMN issue_fingerprint TO issue_fingerprint_bak;
    -- execute the workflow
    ALTER TABLE deal_alert_state RENAME COLUMN issue_fingerprint_bak TO issue_fingerprint;

`Load Previous Alert State` is a `SELECT *` and is unaffected, and
`Mark Deal Still at Risk` only touches `last_seen_at`, so only `Save Alert
State` fails. Reset the state tables first, or the deals will route to REFRESH
and there will be nothing to fail.

## Troubleshooting

### No deals are returned

Check the HubSpot private app scopes and verify that the test deals are open.
Do not interpret an empty response as proof that all pipeline deals have
closed.

### Google Sheets writes fail

Confirm that the service account has access to both spreadsheets and that the
tab names and column headers match the workflow mappings.

### Slack messages fail

Check the bot token, channel IDs and channel membership. The workflow writes
alert state only after delivery is confirmed.

### Slack alerts should include a link to the n8n workflow

All four Slack nodes have "Include Link to Workflow" turned off, so alerts carry
no n8n URL. Turn it back on in the node options if the risk channel is read only
by the team that runs n8n.

### The AI response is rejected

Check the OpenRouter credential and model configuration. The workflow includes
a rule-based fallback for an unusable individual response, but a complete AI
node outage is reported through the error path.

## Tuning the demonstration

The scoring thresholds, inactivity bands, high-value escalation, hygiene
weight, new-deal grace period and trend sensitivity are named constants in the
`Calculate Deal Risk` node. Re-alert sensitivity is configured in
`Decide Action Per Deal`.

The schedule defaults to 08:00. Run the workflow manually first so that the
state and output behavior can be inspected before scheduling it.
