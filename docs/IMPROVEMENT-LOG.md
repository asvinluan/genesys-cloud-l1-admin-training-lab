# Improvement log

Real continuous improvement: find a weak spot, make one change, say WHY, and measure it. Each lesson adds entries here.

| Lesson | Improvement | WHY |
|---|---|---|
| 2 | Pre-upload check that refuses bad audio files | A bad announcement is heard by every caller. Checking once is cheaper than fixing under pressure. |
| 2 | Switchable notice slot (data-table style) for urgent, temporary messages | Cuts "record, upload, republish, test" to "flip one row, test". Same ticket, same audit. Needs an expiry (Drop 2). |
| 2 | Written post-change test call | Only hearing it proves callers hear the right thing. |
| 3 | Holiday coverage check with a 90-day warning | An empty future list is invisible until the first missed holiday. |
| 3 | Emergency runbook (who, which ticket type, check call) | People improvise under pressure. |
| 3 | Boundary tests (08:29/08:30, 17:59/18:00) | Off-by-one-minute faults are the most common schedule bug. |
| 4 | Warning when a queue member lacks the queue skill | The real failure is silent: no error, just no calls. |
| 4 | Leaver removal from queues, not only account disable | A disabled but queued account is a routing hole and a security gap. |
| 4 | Monthly membership comparison to a team-leader file | Drift is invisible until a call is missed. |
| 5 | Ask for an alternate callback number | The caller's own number is often withheld or unanswered. |
| 5 | Validate the number before promising a call | A broken promise costs more trust than not offering. |
| 5 | Tune the callback threshold from reports | 5 minutes is a guess until data says otherwise. |
| 6 | Chat-aware closed message | A message that promises something that is not there damages trust. |
| 6 | Show the reply date on the form confirmation | A date is a promise people can check. |
| 6 | Named owner for the enquiry form | Shared inboxes with no owner fail quietly. |
