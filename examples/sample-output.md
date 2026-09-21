# Sample Output

> **All data on this page is synthetic, created for this portfolio project.**
> These are not real deals, customers, owners, companies or alerts. Every deal
> name is prefixed "Test Deal -" and the numeric IDs are invented.
>
> Every figure below comes from one real execution and is reproducible without a
> HubSpot account. Load `database/sample-data.sql`, pin
> `examples/pin-data-hubspot-deals.json` onto the `Get Open Deals from HubSpot`
> node, and run the workflow. The screenshots in `docs/screenshots/` are from
> that same execution.

---

## The run

Eleven deals scanned in a single execution, chosen so that one run exercises
every decision route the workflow has.

| Deal | Score | Level | Route | Why |
|---|---|---|---|---|
| Enterprise Infrastructure Renewal | 85 | CRITICAL | `NEEDS_AI` | New at-risk deal |
| Public Sector Framework | 75 | CRITICAL | `NEEDS_AI` | New at-risk deal |
| Logistics Platform Expansion | 60 | CRITICAL | `NEEDS_AI` | Level moved HIGH → CRITICAL |
| Partner Co-Sell Expansion | 53 | HIGH | `NEEDS_AI` | New at-risk deal |
| Health Analytics Module | 43 | HIGH | `NEEDS_AI` | New at-risk deal |
| Regional Rollout Phase 2 | 40 | HIGH | `REFRESH` | Unchanged since yesterday |
| Hygiene Gap Pilot | 33 | MODERATE | `NOOP` | Below alerting threshold |
| Midmarket CRM Migration | 23 | MODERATE | `NOOP` | Below alerting threshold |
| Retail Renewal FY26 | 10 | LOW | `RESOLVED` | Recovered |
| Support Tier Upgrade | 0 | LOW | `NOOP` | Clean record |
| Startup Pilot Programme | 0 | LOW | `NOOP` | New deal, hygiene waived |
| Manufacturing Line Upgrade | — | — | reaped | Absent from the scan |

Five Slack alerts, one silent refresh, two resolutions, four deals ignored.

---

## 1. Slack alert, CRITICAL

Posted to the risk channel when a deal crosses into CRITICAL or changes
materially.

```
🚨 CRITICAL DEAL RISK

Deal: Test Deal - Enterprise Infrastructure Renewal
Owner ID: 61204887
Amount: 250,000
Risk: 85/100 (CRITICAL)
Close: 11 days overdue
Why now: NEW_RISK_ALERT

Risk drivers:
• Only one contact associated, so the deal depends on a single relationship.
• Close date 11 days overdue, indicating forecast slippage.
• Close date pushed twice, timeline confidence is weakening.

Recommended action: Engage the single contact to understand the stalled
contract status and identify any outstanding blockers to closing.
```

Score composition:

| Component | Points |
|---|---|
| `SINGLE_THREADED` — one associated contact | 25 |
| `EXPIRED_CLOSE_DATE` — 11 days overdue | 20 |
| `CLOSE_DATE_PUSHED_TWICE` — pushed across two forecast periods | 25 |
| High-value escalation — 250,000, 25% of deal risk capped at 15 | 15 |
| Data quality — no issues on this record | 0 |
| **Final** | **85 → CRITICAL** |

This record has no CRM hygiene problems at all, which is why all three displayed
drivers are revenue risk. The close-date push count is the part a single CRM
snapshot cannot see: on any given day this deal simply has a date, and only the
stored history reveals that it has moved twice.

---

## 2. Slack alert, HIGH

```
⚠️ HIGH DEAL RISK

Deal: Test Deal - Health Analytics Module
Owner ID: 61204913
Amount: 45,000
Risk: 43/100 (HIGH) · NEW
Close: in 22 days
Why now: NEW_RISK_ALERT

Risk drivers:
• Only one contact associated, so the deal depends on a single relationship.
• Activity aging at 16 days, momentum slowing.

Recommended action: Identify and engage a second stakeholder this week
before advancing the deal.
```

Score composition: `SINGLE_THREADED` 25 + `LOSING_MOMENTUM` 18 = **43 → HIGH**.
No hygiene issues on this record either.

`Attach Recommended Action` returns exactly this sentence when a deal's top
issue code is `SINGLE_THREADED` and the model's answer is missing or unusable,
which is what makes an AI hiccup cost a wording change rather than an alert.

---

## 3. What a quiet day looks like

Regional Rollout Phase 2 scored 40 and was HIGH yesterday. Today it scores 40
and is still HIGH, with the same issue fingerprint.

| | Yesterday | Today |
|---|---|---|
| Risk level | HIGH | HIGH |
| Risk score | 40 | 40 |
| Issue fingerprint | `MISSING_NEXT_STEP,STALLED_DEAL` | `MISSING_NEXT_STEP,STALLED_DEAL` |
| Slack | alerted | **silent** |
| `last_seen_at` | yesterday | today |
| `last_alerted_at` | yesterday | **yesterday** |

The deal is routed `REFRESH`: its action-queue row is updated with today's
figures, `last_seen_at` is touched so the cleanup path leaves it alone, and no
message is sent. `docs/screenshots/deal-alert-state-data-table.png` shows this
as a single row where `last_seen_at` is today and `last_alerted_at` is not.

This is the main reason PostgreSQL is in the design. Without it, this deal would
generate an identical alert every morning until someone muted the channel.

---

## 4. Action queue (Google Sheets)

One row per deal that needs attention, updated in place and matched on
`deal_id`. Deals routed `NOOP` never reach this sheet.

| deal_id | deal_name | amount | days_to_close | inactive_days | contacts | risk_level | risk_score | risk_trend | days_at_risk | action_status |
|---|---|---|---|---|---|---|---|---|---|---|
| 31882004417 | Test Deal - Logistics Platform Expansion | 82,000 | 5 | 45 | 3 | CRITICAL | 60 | RISING | 14 | REVIEW_REQUIRED |
| 31882004612 | Test Deal - Health Analytics Module | 45,000 | 22 | 16 | 1 | HIGH | 43 | NEW | 0 | REVIEW_REQUIRED |
| 31882010455 | Test Deal - Enterprise Infrastructure Renewal | 250,000 | −11 | 9 | 1 | CRITICAL | 85 | NEW | 0 | REVIEW_REQUIRED |
| 31882010517 | Test Deal - Public Sector Framework | 96,000 | −20 | 74 | 2 | CRITICAL | 75 | NEW | 0 | REVIEW_REQUIRED |
| 31882010524 | Test Deal - Partner Co-Sell Expansion | 71,000 | 18 | 20 | 3 | HIGH | 53 | NEW | 0 | REVIEW_REQUIRED |
| 31882010461 | Test Deal - Regional Rollout Phase 2 | 54,000 | 60 | 38 | 3 | HIGH | 40 | STABLE | 6 | REVIEW_REQUIRED |
| 31881996204 | *(see note)* | | | | | LOW | 10 | FALLING | 9 | RESOLVED |

The resolved deal's row carries only the fields that changed. On a queue that
already holds that deal, `appendOrUpdate` leaves the rest of the row intact. On
a queue that has just been cleared — as in this capture — it appends instead,
and the unmapped columns land empty. See Known Gaps in
[the architecture document](../docs/architecture.md).

---

## 5. Daily summary (Google Sheets)

One row per run, written even on a day that scanned zero deals, so a gap in this
sheet means the workflow did not run.

| run_timestamp | execution_id | deals_scanned | low | moderate | high | critical | high_value_at_risk | single_threaded | data_quality_only | missing_close_date | exposure_high_critical |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-21 14:28:02 | 127 | 11 | 3 | 2 | 3 | 3 | 1 | 2 | **0** | 1 | $598,000.00 |

Two of these columns are health checks rather than business data.

`data_quality_only` should always read 0, because hygiene issues alone cannot
reach an alerting level. "Hygiene Gap Pilot" is the deliberate stress test: it
has no amount, no owner, no next step, no close date and no associated contact —
65 raw hygiene points — and still only reaches 33, seven short of HIGH.

A jump in `missing_close_date` usually means HubSpot changed how it serialises
dates rather than that salespeople stopped filling the field.

---

## 6. Alert log (Google Sheets)

Append-only, one row per delivered alert. This is the audit trail behind the
suppression logic: if a deal is not in here today, no message was sent.

| alerted_at | deal_id | deal_name | risk_level | risk_score | alert_reason | issue_fingerprint |
|---|---|---|---|---|---|---|
| 14:28:17 | 31882004417 | Test Deal - Logistics Platform Expansion | CRITICAL | 60 | RISK_LEVEL_CHANGED | `MISSING_NEXT_STEP,NEAR_CLOSE_EXECUTION_GAP,STALLED_DEAL` |
| 14:28:17 | 31882010455 | Test Deal - Enterprise Infrastructure Renewal | CRITICAL | 85 | NEW_RISK_ALERT | `CLOSE_DATE_PUSHED_TWICE,EXPIRED_CLOSE_DATE,SINGLE_THREADED` |
| 14:28:17 | 31882010517 | Test Deal - Public Sector Framework | CRITICAL | 75 | NEW_RISK_ALERT | `EXPIRED_CLOSE_DATE,SEVERELY_STALLED_DEAL` |
| 14:28:25 | 31882004612 | Test Deal - Health Analytics Module | HIGH | 43 | NEW_RISK_ALERT | `LOSING_MOMENTUM,SINGLE_THREADED` |
| 14:28:25 | 31882010524 | Test Deal - Partner Co-Sell Expansion | HIGH | 53 | NEW_RISK_ALERT | `CLOSE_DATE_REPEATEDLY_PUSHED,LOSING_MOMENTUM` |

Five rows for eleven deals scanned. Regional Rollout Phase 2 is at HIGH and is
absent, which is the point.

---

## 7. Resolved log (Google Sheets)

| resolved_at | deal_id | resolution_reason | last_risk_level | last_risk_score | new_risk_level | new_risk_score | days_at_risk |
|---|---|---|---|---|---|---|---|
| 14:28:10 | 31881996204 | RISK_IMPROVED | HIGH | 43 | LOW | 10 | 9 |
| 14:28:39 | 31881990877 | NOT_IN_PIPELINE | CRITICAL | 70 | | 0 | 31 |

The first deal recovered: a second contact was added and activity resumed, so it
dropped below the alerting threshold and its state row was deleted.

The second never appeared in the scan at all. It was last seen 90 days ago, well
past the 30-day guard, so the pipeline-exit cleanup closed it out. Its
`deal_tracking` row is deliberately kept, so if the deal ever reopens its
close-date push history is still correct.

---

## 8. Workflow error alert

Posted to a separate engineering channel, never to the risk channel. Failures
from one node are grouped into a single message that names the affected deals.

```
🛑 WORKFLOW ERROR

Node: Save Alert State
Failed items: 3
Execution: 132
Time: 2026-09-21T11:10:00.636Z

Detail:
- 31882004612: NodeOperationError: Column 'issue_fingerprint' does not exist in selected table
- 31882010455: NodeOperationError: Column 'issue_fingerprint' does not exist in selected table
- 31882010461: NodeOperationError: Column 'issue_fingerprint' does not exist in selected table
```

Three deals, one message. The alert names the failing node, the affected deal
IDs and the cause, which is enough to act on without opening n8n.

Because alert state is written only after Slack confirms delivery, and this
failure happens at the state write, those three deals recorded nothing. They
alert again on the next run rather than being silently suppressed. The Slack
messages themselves were delivered normally and the sales channel saw nothing
unusual.

This capture is from a separate execution in which a column was renamed
deliberately to force the failure. See SETUP.md for how to reproduce it.
