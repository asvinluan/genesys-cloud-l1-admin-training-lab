# Honest limits

- This is a **pretend** organisation ("Wattle Group"). It was **not** run against a live Genesys Cloud org. Nothing here logs in to Genesys.
- The commands (`Get-Wg...`) are **teaching simulations**, not real Genesys cmdlets. They show the shape of the work and the reasons.
- Genesys facts (file formats, schedule evaluation order, callback behaviour) are marked as such and come from Genesys help pages. Always re-check the current page: menus and limits change.
- House rules (mono, loudness, file names, 5-minute callback threshold, 90-day holiday warning) are choices made in this lab, not Genesys rules.
- The substitute holiday date used in Lesson 3 must be checked against the official list for your state.
- Tested on PowerShell 7. Windows PowerShell 5.1 is covered by the CI workflow; run `.\tests\Invoke-LabTests.ps1` and report any failure.
