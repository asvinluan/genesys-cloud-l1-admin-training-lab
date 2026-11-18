# genesys-cloud-l1-admin-training-lab

A no-login, PowerShell-only training lab for **Genesys Cloud CX telephony administration**, written in plain English for a Level 1 engineer, with an architect lens on every lesson.

The pretend company is **Wattle Group**: seven phone lines (health sales and service, general enquiries, overseas visitors, insurance, wealth, funeral, wholesale), web chat and an online enquiry form.

## What you need
- Windows PowerShell 5.1 or PowerShell 7
- Optional: `ffmpeg` (Lesson 2 makes and checks test audio)
- **No Genesys account. No OAuth. No internet needed.**

## Start
```powershell
git clone <this repo>
cd genesys-cloud-l1-admin-training-lab
.\Start-Lab.ps1
.\tests\Invoke-LabTests.ps1
```
Then open `lessons/L00.md`.

## Lessons (Drop 1)
| # | Topic |
|---|---|
| 0 | Start here |
| 1 | How a call travels |
| 2 | Announcements and the outage notice |
| 3 | Hours, holidays and emergencies |
| 4 | Queues, skills and people |
| 5 | Callbacks |
| 6 | Online options: chat and the enquiry form |

Coming: data tables, reporting, outbound dialler, DR/BC, evaluating new Genesys features, SME and roadmap.

Every mutating command needs a ticket (`INC`, `RITM` or `CHG` plus 7 digits) and writes an audit entry. State lives in `.state/` (ignored by git); `Reset-WgOrg` restores the start.

See `docs/HONEST-LIMITS.md` and `docs/IMPROVEMENT-LOG.md`. MIT licence.
