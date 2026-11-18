# Runs every check on the pretend org. Needs no login. Works in Windows PowerShell 5.1 and PowerShell 7.
#   .\tests\Invoke-LabTests.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Join-Path $root 'tools') 'Wattle.psm1') -Force
# The tests also look inside the module. These small wrappers reach its internal helpers.
$mod = Get-Module Wattle
function Get-WgState { & $mod { Get-WgState } }
function Save-WgState { param($State) & $mod { param($s) Save-WgState $s } $State }
function Find-WgItem { param($List, [string]$Id) $List | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Get-WgEligible { param($State, $Queue) & $mod { param($s, $q) Get-WgEligible $s $q } $State $Queue }
function Get-WgScheduleState { param($State, [string]$GroupId, $At, [string]$EmergencyGroupId) & $mod { param($s, $g, $a, $e) Get-WgScheduleState -State $s -GroupId $g -At $a -EmergencyGroupId $e } $State $GroupId $At $EmergencyGroupId }
$script:pass = 0; $script:fail = 0
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $ok = $false
    try { $ok = [bool](& $Body) } catch { $ok = $false; Write-Host ("        error: " + $_.Exception.Message) -ForegroundColor DarkYellow }
    if ($ok) { $script:pass++; Write-Host ("  PASS  " + $Name) -ForegroundColor Green } else { $script:fail++; Write-Host ("  FAIL  " + $Name) -ForegroundColor Red }
}
function Quiet { param([scriptblock]$B) $null = & $B 6>&1 }   # run a command and hide its screen output

Reset-WgOrg -Quiet
Write-Host 'Call paths'
Test-Case 'open hours, press 1 on Health -> Members queue' { $r = Trace-WgCall -Number '+61355500401' -At '2026-11-16 10:15' -Keys 1 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Queue -eq 'Q-HS-Members' -and $r.ScheduleState -eq 'open' }
Test-Case 'Saturday -> closed message, disconnect'     { $r = Trace-WgCall -Number '+61355500401' -At '2026-11-14 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.ScheduleState -eq 'closed' -and $r.Outcome -eq 'disconnected' }
Test-Case 'public holiday beats open hours'            { $r = Trace-WgCall -Number '+61355500401' -At '2026-12-25 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.ScheduleState -eq 'holiday' }
Test-Case '08:29 is closed, 08:30 is open'             { $a = Test-WgSchedule -At '2026-11-16 08:29' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $b = Test-WgSchedule -At '2026-11-16 08:30' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $a.State -eq 'closed' -and $b.State -eq 'open' }
Test-Case '18:00 sharp is closed (end is exclusive)'   { $a = Test-WgSchedule -At '2026-11-16 18:00' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $a.State -eq 'closed' }
Test-Case 'wrong key twice -> default queue'           { $r = Trace-WgCall -Number '+61355500401' -At '2026-11-16 10:15' -Keys 7,8 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Queue -eq 'Q-HS-Members' }
Test-Case 'silence -> menu repeats, then default'      { $r = Trace-WgCall -Number '+61355500402' -At '2026-11-16 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Queue -eq 'Q-GEN-Other' }
Test-Case 'overseas line has no menu'                  { $r = Trace-WgCall -Number '+61355500403' -At '2026-11-16 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Queue -eq 'Q-HS-Overseas' }
Test-Case 'unknown number is not in service'           { $r = Trace-WgCall -Number '+61355509999' -At '2026-11-16 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Outcome -eq 'none' }
Test-Case 'number typed with a leading 0 still works'  { $r = Trace-WgCall -Number '(03) 5550 0404' -At '2026-11-16 10:15' -Keys 1 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Queue -eq 'Q-INS-Claims' }

Write-Host 'Emergency group'
Test-Case 'ticket number is required and checked'      { $threw = $false; try { Set-WgEmergencyGroup -Id EG-Phone -Active $true -Ticket 'abc' } catch { $threw = $true }; $threw }
Test-Case 'emergency switch overrides open hours'      { Quiet { Set-WgEmergencyGroup -Id EG-Phone -Active $true -Ticket INC0000101 }; $r = Trace-WgCall -Number '+61355500401' -At '2026-11-16 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; Quiet { Set-WgEmergencyGroup -Id EG-Phone -Active $false -Ticket INC0000102 }; $r.ScheduleState -eq 'emergency' }
Test-Case 'switch is in the audit log'                 { @((Get-WgState).audit).Count -ge 2 }

Write-Host 'Holidays'
Test-Case 'warns when the list ends within 90 days'    { (Test-WgHolidayCoverage -Today '2026-11-13' -PassThru 6>&1 | Where-Object { $_ -is [string] }) -eq 'warn' }
Test-Case 'fails when every holiday is past'           { (Test-WgHolidayCoverage -Today '2027-06-01' -PassThru 6>&1 | Where-Object { $_ -is [string] }) -eq 'fail' }

Write-Host 'Queues and people'
Test-Case 'member without the skill is added with a warning' { Quiet { Add-WgQueueMember -Queue Q-WLT-New -User U13 -Ticket RITM0000201 }; $e = Get-WgEligible (Get-WgState) (Find-WgItem (Get-WgState).queues 'Q-WLT-New') | Where-Object { $_.UserId -eq 'U13' }; ($e.Eligible -eq $false) }
Test-Case 'a queue with nobody eligible is flagged as stuck' { $s = Get-WgState; $q = Find-WgItem $s.queues 'Q-WHO-Desk'; $q.members = @(); Save-WgState $s; $r = Trace-WgCall -Number '+61355500407' -At '2026-11-16 10:15' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Outcome -eq 'stuck' }
Reset-WgOrg -Quiet
Test-Case 'leaver is removed from every queue'         { Quiet { Disable-WgUser -User U02 -Ticket RITM0000301 }; $s = Get-WgState; $in = @($s.queues | Where-Object { @($_.members) -contains 'U02' }); ($in.Count -eq 0) -and (-not (Find-WgItem $s.users 'U02').active) }
Test-Case 'a disabled person cannot be added'          { Quiet { Add-WgQueueMember -Queue Q-HS-Sales -User U02 -Ticket RITM0000302 }; @((Find-WgItem (Get-WgState).queues 'Q-HS-Sales').members) -notcontains 'U02' }
Reset-WgOrg -Quiet
Test-Case 'membership check finds a missing person'    { $r = Compare-WgQueueMembership -IntendedCsv (Join-Path (Join-Path $root 'automation') 'intended-membership.csv') -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Missing -eq 1 -and $r.Extra -eq 0 }

Write-Host 'Callbacks'
Reset-WgOrg -Quiet
Test-Case 'long wait -> callback offered and accepted' { $r = Trace-WgCall -Number '+61355500401' -At '2026-11-16 10:15' -Keys 2 -WaitMinutes 9 -AcceptCallback -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.Callback -and @((Get-WgState).callbacks).Count -eq 1 }
Test-Case 'short wait -> no offer'                     { Reset-WgOrg -Quiet; $r = Trace-WgCall -Number '+61355500401' -At '2026-11-16 10:15' -Keys 2 -WaitMinutes 2 -AcceptCallback -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; (-not $r.Callback) }
Test-Case 'queue with callbacks off -> no offer'       { Reset-WgOrg -Quiet; $r = Trace-WgCall -Number '+61355500402' -At '2026-11-16 10:15' -Keys 3 -WaitMinutes 12 -AcceptCallback -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; (-not $r.Callback) }
Test-Case 'bad callback number is refused'             { Reset-WgOrg -Quiet; $r = Trace-WgCall -Number '+61355500401' -At '2026-11-16 10:15' -Keys 2 -WaitMinutes 9 -AcceptCallback -CallbackNumber '12345' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; (-not $r.Callback) }
Test-Case 'web callback form queues a callback'        { Reset-WgOrg -Quiet; Quiet { Request-WgCallback -Queue Q-HS-Sales -Number '0491 570 156' -Name 'Pat' -At '2026-11-16 10:00' }; @((Get-WgState).callbacks).Count -eq 1 }
Test-Case 'web callback with a bad number is refused'  { Reset-WgOrg -Quiet; Quiet { Request-WgCallback -Queue Q-HS-Sales -Number '99' -At '2026-11-16 10:00' }; @((Get-WgState).callbacks).Count -eq 0 }

Write-Host 'Online options'
Test-Case 'chat is open at 19:00 while phones are closed' { $c = Get-WgScheduleState -State (Get-WgState) -GroupId SG-Chat -At ([datetime]'2026-11-16 19:00') -EmergencyGroupId ''; $p = Get-WgScheduleState -State (Get-WgState) -GroupId SG-Phone -At ([datetime]'2026-11-16 19:00') -EmergencyGroupId ''; $c.State -eq 'open' -and $p.State -eq 'closed' }
Test-Case 'chat is closed at 20:00'                    { (Get-WgScheduleState -State (Get-WgState) -GroupId SG-Chat -At ([datetime]'2026-11-16 20:00') -EmergencyGroupId '').State -eq 'closed' }
Test-Case 'form reply window skips weekend and holiday' {
    $o = (Get-WgEnquiryDue -Submitted '2026-12-22' 6>&1 | Out-String)
    ($o -match 'Mon 28 Dec') -and ($o -match 'Wed 30 Dec') }

Write-Host 'Notices and announcements'
Test-Case 'outage notice plays on lines where it is ON' { Reset-WgOrg -Quiet; $o = (Trace-WgCall -Number '+61355500405' -At '2026-11-16 10:15' -Keys 1 6>&1 | Out-String); $o -match 'worldwide technology outage' }
Test-Case 'switching the notice OFF removes it, no republish' { Quiet { Set-WgNotice -Line L5 -Active $false -Ticket CHG0000401 }; $o = (Trace-WgCall -Number '+61355500405' -At '2026-11-16 10:15' -Keys 1 6>&1 | Out-String); ($o -notmatch 'worldwide technology outage') -and (@((Get-WgState).flows | Where-Object { $_.id -eq 'IVR-Wealth-Open' }).publishedVersion -eq 1) }

$ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wg-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
function New-Wav {
    param([string]$Name, [int]$Rate = 8000, [int]$Channels = 1, [double]$Volume = 1.0, [int]$Seconds = 3, [string]$Codec = 'pcm_s16le')
    $p = Join-Path $tmp $Name
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $ff.Source -y -v error -f lavfi -i ("sine=frequency=440:duration=" + $Seconds) -af ("volume=" + $Volume) -ar $Rate -ac $Channels -c:a $Codec $p 2>&1 | Out-Null
    $ErrorActionPreference = $prev
    Set-Content -Path ([System.IO.Path]::ChangeExtension($p, '.txt')) -Value 'Test words.' -Encoding UTF8
    return $p
}
if ($ff) {
    Test-Case 'good announcement passes'                 { $f = New-Wav 'health-notice-20261114-v2.wav' -Volume 3.0; (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'mu-law 8 kHz passes (Genesys converts to it)' { $f = New-Wav 'health-notice-20261114-v3.wav' -Volume 3.0 -Codec pcm_mulaw; (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case '44.1 kHz is rejected'                     { $f = New-Wav 'health-notice-20261114-v4.wav' -Rate 44100 -Volume 3.0; -not (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'stereo is rejected'                       { $f = New-Wav 'health-notice-20261114-v5.wav' -Channels 2 -Volume 3.0; -not (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'clipping is rejected'                     { $f = New-Wav 'health-notice-20261114-v6.wav' -Volume 8.0; -not (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'a very quiet file is rejected'            { $f = New-Wav 'health-notice-20261114-v7.wav' -Volume 0.01; -not (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'MP3 is rejected'                          { $m = Join-Path $tmp 'health-notice-20261114-v8.mp3'; $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; & $ff.Source -y -v error -f lavfi -i 'sine=frequency=440:duration=2' -ar 8000 -ac 1 $m 2>&1 | Out-Null; $ErrorActionPreference = $prev; Set-Content ([System.IO.Path]::ChangeExtension($m, '.txt')) 'x'; -not (Test-WgAnnouncement -Path $m -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'bad file name is rejected'                { $f = New-Wav 'My new message FINAL.wav' -Volume 3.0; -not (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'bad ticket is rejected'                   { $f = New-Wav 'health-notice-20261114-v9.wav' -Volume 3.0; -not (Test-WgAnnouncement -Path $f -Ticket 'hello' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'missing script text is rejected'          { $f = New-Wav 'health-notice-20261114-v10.wav' -Volume 3.0; Remove-Item ([System.IO.Path]::ChangeExtension($f, '.txt')); -not (Test-WgAnnouncement -Path $f -Ticket RITM0000501 -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }).Pass }
    Test-Case 'upload alone leaves flows on the OLD version, republish fixes it' {
        Reset-WgOrg -Quiet
        $f = New-Wav 'wealth-greeting-20261114-v2.wav' -Volume 3.0
        Quiet { Set-WgPromptAudio -Prompt P-Greet-Wealth -Path $f -Ticket RITM0000601 -Text 'Thanks for calling Wattle Wealth. New words.' }
        $before = (Trace-WgCall -Number '+61355500405' -At '2026-11-16 10:15' -Keys 1 6>&1 | Out-String)
        $stale = (Get-WgPromptUsage -StaleOnly 6>&1 | Out-String)
        Quiet { Publish-WgFlow -Flow IVR-Wealth-Open -Ticket RITM0000601 }
        $after = (Trace-WgCall -Number '+61355500405' -At '2026-11-16 10:15' -Keys 1 6>&1 | Out-String)
        ($before -notmatch 'New words') -and ($stale -match 'STALE') -and ($after -match 'New words') }
}
else { Write-Host '  SKIP  audio tests (ffmpeg not found). Install it with: winget install Gyan.FFmpeg' -ForegroundColor Yellow }
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host 'Design checks (added from Lessons 3, 4 and 6)'
Test-Case 'closed message offers chat only when chat is open' {
    Reset-WgOrg -Quiet
    $sat = (Trace-WgCall -Number '+61355500401' -At '2026-11-14 10:15' 6>&1 | Out-String)
    $eve = (Trace-WgCall -Number '+61355500401' -At '2026-11-16 19:00' 6>&1 | Out-String)
    ($sat -match 'P-Closed-NoChat') -and ($eve -match 'P-Closed ') -and ($eve -match 'chat with us online') }
Test-Case 'adding a holiday changes the call path'     { Reset-WgOrg -Quiet; Quiet { Add-WgHoliday -Date '2026-12-28' -Name 'Boxing Day (substitute)' -Ticket CHG0000777 }; $r = Trace-WgCall -Number '+61355500401' -At '2026-12-28 10:00' -PassThru 6>&1 | Where-Object { $_ -is [pscustomobject] }; $r.ScheduleState -eq 'holiday' }
Test-Case 'a skill makes a queue member eligible'      { Reset-WgOrg -Quiet; Quiet { Add-WgQueueMember -Queue Q-WLT-New -User U13 -Ticket RITM0000201 }; Quiet { Add-WgUserSkill -User U13 -Skill Wealth -Proficiency 3 -Ticket RITM0000202 }; $e = Get-WgEligible (Get-WgState) (Find-WgItem (Get-WgState).queues 'Q-WLT-New') | Where-Object { $_.UserId -eq 'U13' }; $e.Eligible }
Test-Case 'unknown skill is refused'                   { Reset-WgOrg -Quiet; Quiet { Add-WgUserSkill -User U13 -Skill Juggling -Ticket RITM0000203 }; -not (@((Find-WgItem (Get-WgState).users 'U13').skills) | Where-Object { $_.skill -eq 'Juggling' }) }

Write-Host 'Documents'
Test-Case 'call map lists every line'                  { Reset-WgOrg -Quiet; $p = Join-Path ([System.IO.Path]::GetTempPath()) 'wg-callmap.md'; Quiet { Export-WgCallMap -Path $p }; $t = Get-Content -Raw $p; Remove-Item $p; ($t -match 'L1 - Health') -and ($t -match 'L7 - Wholesale') }

Reset-WgOrg -Quiet
Write-Host ''
Write-Host ('{0} passed, {1} failed' -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
