# Wattle.psm1  -  a PRETEND Genesys Cloud org for training.
# No sign-in, no network, no real Genesys. Everything reads and writes one local file (.state\org.json).
# Written for Windows PowerShell 5.1 and PowerShell 7. Every name, number and person is invented.
#
# Real Genesys Cloud needs an OAuth client for the same jobs. Here we skip that on purpose, so you can
# practise the thinking (what to check, what to change, what the caller hears) without any account.

$script:Root       = Split-Path -Parent $PSScriptRoot
$script:SeedPath   = Join-Path (Join-Path $script:Root 'org') 'seed.json'
$script:StateDir   = Join-Path $script:Root '.state'
$script:StatePath  = Join-Path $script:StateDir 'org.json'
$script:SpecPath   = Join-Path (Join-Path $script:Root 'announcements') 'spec.json'
$script:TicketPattern = '^(INC|RITM|CHG)\d{7}$'

# ---------------------------------------------------------------- small helpers
function Out-Wg {
    param([string]$Text, [string]$Kind = 'info')
    switch ($Kind) {
        'step' { Write-Host ('==> ' + $Text) -ForegroundColor Cyan }
        'ok'   { Write-Host ('  OK   ' + $Text) -ForegroundColor Green }
        'warn' { Write-Host (' WARN  ' + $Text) -ForegroundColor Yellow }
        'fail' { Write-Host (' FAIL  ' + $Text) -ForegroundColor Red }
        'hear' { Write-Host ('       Caller hears: "' + $Text + '"') -ForegroundColor Magenta }
        default { Write-Host $Text }
    }
}
function Out-WgTable {
    param($Rows)
    $text = ($Rows | Format-Table -AutoSize | Out-String -Width 160).TrimEnd()
    Write-Host $text
}
function ConvertTo-WgNumber {
    param([string]$Number)
    $n = ($Number -replace '[\s\-\(\)]', '')
    if ($n.StartsWith('0')) { $n = '+61' + $n.Substring(1) }
    if (-not $n.StartsWith('+')) { $n = '+' + $n }
    return $n
}
function Format-WgNumber {
    param([string]$Number)
    if ($Number -match '^\+61(\d)(\d{4})(\d{4})$') { return ('+61 {0} {1} {2}' -f $Matches[1], $Matches[2], $Matches[3]) }
    return $Number
}
function Get-WgState {
    if (-not (Test-Path $script:StatePath)) { Reset-WgOrg -Quiet }
    return (Get-Content -Raw -Encoding UTF8 -Path $script:StatePath | ConvertFrom-Json)
}
function Save-WgState {
    param($State)
    if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir | Out-Null }
    $State | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path $script:StatePath
}
function Add-WgAudit {
    param($State, [string]$Ticket, [string]$Action, [string]$Target, [string]$Detail)
    $entry = [pscustomobject]@{
        when   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        who    = 'You (Telephony Administrator)'
        ticket = $Ticket
        action = $Action
        target = $Target
        detail = $Detail
    }
    $State.audit = @($State.audit) + @($entry)
}
function Find-WgItem {
    param($List, [string]$Id)
    return ($List | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}
function Get-WgPromptText {
    param($State, [string]$PromptId, [int]$Version)
    $p = Find-WgItem $State.prompts $PromptId
    if (-not $p) { return '(prompt not found)' }
    $v = $p.versions | Where-Object { $_.v -eq $Version } | Select-Object -First 1
    if (-not $v) { return '(version not found)' }
    return $v.text
}
function Get-WgSnapshotVersion {
    param($Flow, [string]$PromptId)
    $row = $Flow.publishedPrompts | Where-Object { $_.prompt -eq $PromptId } | Select-Object -First 1
    if ($row) { return [int]$row.version }
    return 0
}
function Get-WgEligible {
    # Who could actually be alerted for this queue: active members who hold every skill the queue asks for.
    param($State, $Queue)
    $out = @()
    foreach ($uid in @($Queue.members)) {
        $u = Find-WgItem $State.users $uid
        if (-not $u) { continue }
        $missing = @()
        $total = 0
        foreach ($sk in @($Queue.skills)) {
            $has = @($u.skills) | Where-Object { $_.skill -eq $sk } | Select-Object -First 1
            if ($has) { $total += [int]$has.proficiency } else { $missing += $sk }
        }
        $avg = 0
        if (@($Queue.skills).Count -gt 0 -and $missing.Count -eq 0) { $avg = [math]::Round($total / @($Queue.skills).Count, 1) }
        $out += [pscustomobject]@{ UserId = $u.id; Name = $u.name; Active = [bool]$u.active; Missing = ($missing -join ','); AvgProficiency = $avg
            Eligible = ([bool]$u.active -and $missing.Count -eq 0) }
    }
    return $out
}
function Test-WgTicket {
    param([string]$Ticket)
    return ($Ticket -match $script:TicketPattern)
}

# ---------------------------------------------------------------- the pretend org
function Reset-WgOrg {
    <#
    .SYNOPSIS  Puts the pretend org back to its starting state (org\seed.json). Use it any time you want a clean start.
    #>
    [CmdletBinding()] param([switch]$Quiet)
    if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir | Out-Null }
    Copy-Item -Path $script:SeedPath -Destination $script:StatePath -Force
    if (-not $Quiet) { Out-Wg 'Pretend org reset to the starting data.' 'ok' }
}
function Get-WgLine {
    <#
    .SYNOPSIS  Lists the phone numbers (lines) the pretend company owns. Real Genesys: Telephony > DIDs / number management.
    #>
    [CmdletBinding()] param([string]$Number)
    $s = Get-WgState
    $rows = @($s.lines)
    if ($Number) { $n = ConvertTo-WgNumber $Number; $rows = @($rows | Where-Object { $_.number -eq $n }) }
    $view = $rows | ForEach-Object {
        [pscustomobject]@{ Id = $_.id; Name = $_.name; Number = (Format-WgNumber $_.number); CallRoute = $_.callRoute; Depth = $_.kind }
    }
    Out-WgTable $view
}
function Describe-WgStep {
    param($Step)
    switch ($Step.op) {
        'notice'  { return ('Look up the notice slot for line {0} in data table "notices". If it is ON, play that notice first.' -f $Step.line) }
        'play'    { return ('Play prompt {0}' -f $Step.prompt) }
        'menu'    {
            $opts = @()
            foreach ($p in $Step.options.PSObject.Properties) { $opts += ('{0} = {1} -> {2}' -f $p.Name, $p.Value.label, $p.Value.queue) }
            return ('Menu: play {0}, wait {1} s, {2} retry. Keys: {3}. No input after the retries -> {4}' -f $Step.prompt, $Step.timeoutSeconds, $Step.retries, ($opts -join '; '), $Step.onNoInput)
        }
        'transfer' { return ('Transfer to queue {0}' -f $Step.queue) }
        'playIfOpen' { return ('Check schedule group {0}. If OPEN play {1}, otherwise play {2}.' -f $Step.group, $Step.openPrompt, $Step.closedPrompt) }
        'disconnect' { return 'Disconnect' }
        'holdMusic' { return 'Play hold music' }
        'callbackOffer' { return ('If the estimated wait is {0} minutes or more: play {1} and offer a callback (key 1). On key 1: create the callback, play {2}.' -f $Step.ewtMinutesAtLeast, $Step.prompt, $Step.confirmPrompt) }
        default { return ('Step: ' + $Step.op) }
    }
}
function Get-WgCallRoute {
    <#
    .SYNOPSIS  Shows a call route: which flow runs when the line is open, closed, on a holiday or in an emergency.
               Real Genesys: Call Routing (a route maps a dialled number to flows).
    #>
    [CmdletBinding()] param([string]$Id)
    $s = Get-WgState
    $routes = @($s.callRoutes)
    if ($Id) { $routes = @($routes | Where-Object { $_.id -eq $Id }) }
    foreach ($r in $routes) {
        Out-Wg ('Call route {0}  ({1})' -f $r.id, $r.name) 'step'
        $nums = @($s.lines | Where-Object { $_.callRoute -eq $r.id } | ForEach-Object { Format-WgNumber $_.number })
        Out-Wg ('  Numbers pointing here : ' + ($nums -join ', '))
        Out-Wg ('  Schedule group        : ' + $r.scheduleGroup)
        Out-Wg ('  Emergency group       : {0}  (route closes for emergencies: {1})' -f $r.emergencyGroup, $r.closesForEmergency)
        foreach ($st in 'open', 'closed', 'holiday', 'emergency') {
            $fid = $r.flows.$st
            $f = Find-WgItem $s.flows $fid
            $v = ''
            if ($f) { $v = ('published v{0}' -f $f.publishedVersion) }
            Out-Wg ('  {0,-9} flow        : {1}  ({2})' -f $st, $fid, $v)
        }
    }
}
function Get-WgFlow {
    <#
    .SYNOPSIS  Shows a flow (what the caller experiences, step by step). Real Genesys: Architect > Flows.
    #>
    [CmdletBinding()] param([string]$Id, [switch]$Steps)
    $s = Get-WgState
    $flows = @($s.flows)
    if ($Id) { $flows = @($flows | Where-Object { $_.id -eq $Id }) }
    if (-not $Id -and -not $Steps) {
        Out-WgTable ($flows | ForEach-Object { [pscustomobject]@{ Id = $_.id; Name = $_.name; Type = $_.type; Published = ('v' + $_.publishedVersion) } })
        return
    }
    foreach ($f in $flows) {
        Out-Wg ('Flow {0}  ({1}, {2}, published v{3})' -f $f.id, $f.name, $f.type, $f.publishedVersion) 'step'
        $i = 1
        foreach ($st in @($f.steps)) { Out-Wg ('  {0}. {1}' -f $i, (Describe-WgStep $st)); $i++ }
    }
}
function Get-WgPrompt {
    <#
    .SYNOPSIS  Lists prompts (the audio the caller hears) and their versions. Real Genesys: Architect > Prompts.
    #>
    [CmdletBinding()] param([string]$Id)
    $s = Get-WgState
    $rows = @($s.prompts)
    if ($Id) { $rows = @($rows | Where-Object { $_.id -eq $Id }) }
    foreach ($p in $rows) {
        Out-Wg ('Prompt {0}  ({1}, current version v{2})' -f $p.id, $p.purpose, $p.current) 'step'
        foreach ($v in @($p.versions)) {
            Out-Wg ('  v{0}  {1}  file {2}  ticket {3}' -f $v.v, $v.date, $v.file, $v.ticket)
            Out-Wg ('      "{0}"' -f $v.text)
        }
    }
}
function Get-WgPromptUsage {
    <#
    .SYNOPSIS  Shows which version of each prompt every published flow is really playing.
               This is the "did I forget to republish?" check.
    #>
    [CmdletBinding()] param([switch]$StaleOnly)
    $s = Get-WgState
    $rows = @()
    foreach ($f in @($s.flows)) {
        foreach ($row in @($f.publishedPrompts)) {
            $p = Find-WgItem $s.prompts $row.prompt
            $status = 'ok'
            if ([int]$row.version -ne [int]$p.current) { $status = 'STALE - republish the flow' }
            $rows += [pscustomobject]@{ Flow = $f.id; Prompt = $row.prompt; FlowPlays = ('v' + $row.version); Latest = ('v' + $p.current); Status = $status }
        }
    }
    if ($StaleOnly) { $rows = @($rows | Where-Object { $_.Status -ne 'ok' }) }
    if ($rows.Count -eq 0) { Out-Wg 'Every published flow is playing the latest version of every prompt.' 'ok'; return }
    Out-WgTable $rows
}

# ---------------------------------------------------------------- schedules
function Get-WgScheduleState {
    # Genesys checks, in this order: emergency, holiday, then open / closed. (Source: Genesys Resource Center, "Operating schedule groups".)
    param($State, [string]$GroupId, [datetime]$At, [string]$EmergencyGroupId)
    $g = Find-WgItem $State.scheduleGroups $GroupId
    if (-not $g) { return [pscustomobject]@{ State = 'unknown'; Reason = ('schedule group {0} not found' -f $GroupId) } }
    if ($EmergencyGroupId) {
        $e = Find-WgItem $State.emergencyGroups $EmergencyGroupId
        if ($e -and $e.active) { return [pscustomobject]@{ State = 'emergency'; Reason = ('emergency group {0} is ACTIVE' -f $e.id) } }
    }
    $day = $At.ToString('yyyy-MM-dd')
    foreach ($sid in @($g.holiday)) {
        $sch = Find-WgItem $State.schedules $sid
        foreach ($h in @($sch.dates)) {
            if ($h.date -eq $day) { return [pscustomobject]@{ State = 'holiday'; Reason = ('{0} is a holiday ({1})' -f $day, $h.name) } }
        }
    }
    foreach ($sid in @($g.open)) {
        $sch = Find-WgItem $State.schedules $sid
        if (@($sch.days) -contains $At.DayOfWeek.ToString()) {
            $start = [timespan]$sch.start
            $end = [timespan]$sch.end
            if ($At.TimeOfDay -ge $start -and $At.TimeOfDay -lt $end) {
                return [pscustomobject]@{ State = 'open'; Reason = ('{0} {1} is inside {2} {3}-{4}' -f $At.DayOfWeek, $At.ToString('HH:mm'), $sch.id, $sch.start, $sch.end) }
            }
        }
    }
    return [pscustomobject]@{ State = 'closed'; Reason = ('{0} {1} is outside every open schedule' -f $At.DayOfWeek, $At.ToString('HH:mm')) }
}
function Get-WgScheduleGroup {
    <#
    .SYNOPSIS  Shows schedule groups with their open hours and holidays. Real Genesys: Routing > Schedule Groups / Schedules.
    #>
    [CmdletBinding()] param([string]$Id)
    $s = Get-WgState
    $rows = @($s.scheduleGroups)
    if ($Id) { $rows = @($rows | Where-Object { $_.id -eq $Id }) }
    foreach ($g in $rows) {
        Out-Wg ('Schedule group {0}  ({1}, time zone {2})' -f $g.id, $g.name, $g.timeZone) 'step'
        foreach ($sid in @($g.open)) {
            $sch = Find-WgItem $s.schedules $sid
            Out-Wg ('  OPEN     {0}: {1}  {2}-{3}' -f $sch.id, (@($sch.days) -join ','), $sch.start, $sch.end)
        }
        foreach ($sid in @($g.holiday)) {
            $sch = Find-WgItem $s.schedules $sid
            Out-Wg ('  HOLIDAY  {0}: {1} dates' -f $sch.id, @($sch.dates).Count)
            foreach ($d in @($sch.dates)) { Out-Wg ('           {0}  {1}' -f $d.date, $d.name) }
        }
    }
}
function Test-WgSchedule {
    <#
    .SYNOPSIS  Asks "would this line be open, closed, on holiday or in emergency at this moment?"
               Real Genesys: you would place a test call or use the flow's schedule evaluation, then read the result.
    #>
    [CmdletBinding()] param([string]$Group = 'SG-Phone', [Parameter(Mandatory)][datetime]$At, [string]$EmergencyGroup = 'EG-Phone', [switch]$PassThru)
    $s = Get-WgState
    $r = Get-WgScheduleState -State $s -GroupId $Group -At $At -EmergencyGroupId $EmergencyGroup
    Out-Wg ('{0}  {1}  ->  {2}' -f $Group, $At.ToString('ddd dd MMM yyyy HH:mm'), $r.State.ToUpper()) 'step'
    Out-Wg ('  Why: ' + $r.Reason)
    if ($PassThru) { return $r }
}
function Test-WgHolidayCoverage {
    <#
    .SYNOPSIS  Warns when the holiday list is about to run out. Missing holidays are a classic cause of "calls went down the open path on a public holiday".
    #>
    [CmdletBinding()] param([datetime]$Today = (Get-Date), [int]$WarnDays = 90, [switch]$PassThru)
    $s = Get-WgState
    $sch = Find-WgItem $s.schedules 'SCH-Holidays'
    $dates = @($sch.dates | ForEach-Object { [datetime]$_.date } | Sort-Object)
    $future = @($dates | Where-Object { $_ -ge $Today.Date })
    $result = 'ok'
    if ($future.Count -eq 0) { Out-Wg 'Every holiday in the list is in the past. Add next year now.' 'fail'; $result = 'fail' }
    else {
        $last = $dates[$dates.Count - 1]
        $away = [int]($last - $Today.Date).TotalDays
        Out-Wg ('The list has {0} holidays. The last is {1}, {2} days away.' -f $dates.Count, $last.ToString('yyyy-MM-dd'), $away)
        if ($away -lt $WarnDays) { Out-Wg ('The list ends in less than {0} days. Add next year''s dates before then.' -f $WarnDays) 'warn'; $result = 'warn' }
        else { Out-Wg 'Holiday list runs far enough ahead.' 'ok' }
    }
    if ($PassThru) { return $result }
}
function Get-WgEmergencyGroup {
    <# .SYNOPSIS Shows emergency groups (the "switch" that sends every call to the emergency flow). Real Genesys: Routing > Emergency Groups. #>
    [CmdletBinding()] param()
    $s = Get-WgState
    Out-WgTable ($s.emergencyGroups | ForEach-Object { [pscustomobject]@{ Id = $_.id; Name = $_.name; Active = $_.active } })
}
function Set-WgEmergencyGroup {
    <# .SYNOPSIS Turns an emergency group on or off. Needs a ticket number, and is recorded in the audit log. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][bool]$Active,
          [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $e = Find-WgItem $s.emergencyGroups $Id
    if (-not $e) { Out-Wg ('No emergency group called ' + $Id) 'fail'; return }
    $e.active = $Active
    Add-WgAudit -State $s -Ticket $Ticket -Action 'emergency-group' -Target $Id -Detail ('active=' + $Active)
    Save-WgState $s
    Out-Wg ('Emergency group {0} is now {1}.' -f $Id, $(if ($Active) { 'ACTIVE: every phone line plays the emergency message' } else { 'OFF: normal routing' })) 'ok'
}

# ---------------------------------------------------------------- queues and people
function Get-WgQueue {
    <#
    .SYNOPSIS  Shows queues, their members and who could really be alerted. Real Genesys: Contact Center > Queues.
    #>
    [CmdletBinding()] param([string]$Id)
    $s = Get-WgState
    $rows = @($s.queues)
    if ($Id) { $rows = @($rows | Where-Object { $_.id -eq $Id }) }
    if (-not $Id) {
        Out-WgTable ($rows | ForEach-Object {
            $el = @(Get-WgEligible $s $_ | Where-Object { $_.Eligible })
            [pscustomobject]@{ Id = $_.id; Name = $_.name; Skills = (@($_.skills) -join ','); Members = @($_.members).Count; CanTakeCalls = $el.Count; Callback = $_.callbacksEnabled }
        })
        return
    }
    foreach ($q in $rows) {
        Out-Wg ('Queue {0}  ({1})' -f $q.id, $q.name) 'step'
        Out-Wg ('  Routing method {0}, evaluation {1}, service level target {2}, in-queue flow {3}, callbacks {4}' -f $q.routingMethod, $q.evaluationMethod, $q.serviceLevelTarget, $q.inQueueFlow, $q.callbacksEnabled)
        Out-Wg ('  Skills the queue asks for: ' + $(if (@($q.skills).Count) { (@($q.skills) -join ', ') } else { '(none)' }))
        Out-WgTable (Get-WgEligible $s $q | ForEach-Object {
            [pscustomobject]@{ Member = $_.Name; Active = $_.Active; MissingSkills = $_.Missing; Proficiency = $_.AvgProficiency; WillBeAlerted = $_.Eligible } })
    }
}
function Get-WgUser {
    <# .SYNOPSIS Shows people, their role, groups and skills. Real Genesys: Admin > People and Permissions > People. #>
    [CmdletBinding()] param([string]$Id)
    $s = Get-WgState
    $rows = @($s.users)
    if ($Id) { $rows = @($rows | Where-Object { $_.id -eq $Id -or $_.email -eq $Id }) }
    Out-WgTable ($rows | ForEach-Object {
        $r = Find-WgItem $s.roles $_.role
        $gn = @($_.groups | ForEach-Object { (Find-WgItem $s.groups $_).name })
        [pscustomobject]@{ Id = $_.id; Name = $_.name; Role = $r.name; Groups = ($gn -join ' / '); Skills = (@($_.skills | ForEach-Object { $_.skill + ':' + $_.proficiency }) -join ' '); Active = $_.active }
    })
}
function Get-WgRole {
    <# .SYNOPSIS Shows roles and what each one allows. Real Genesys: Admin > People and Permissions > Roles. #>
    [CmdletBinding()] param()
    $s = Get-WgState
    foreach ($r in @($s.roles)) {
        Out-Wg ('Role {0}  ({1})' -f $r.id, $r.name) 'step'
        foreach ($p in @($r.permissions)) { Out-Wg ('  ' + $p) }
    }
}
function Add-WgQueueMember {
    <# .SYNOPSIS Adds a person to a queue. Warns if they lack a skill the queue needs (they would be a member who never gets a call). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Queue, [Parameter(Mandatory)][string]$User,
          [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $q = Find-WgItem $s.queues $Queue
    $u = $s.users | Where-Object { $_.id -eq $User -or $_.email -eq $User } | Select-Object -First 1
    if (-not $q) { Out-Wg ('No queue called ' + $Queue) 'fail'; return }
    if (-not $u) { Out-Wg ('No person called ' + $User) 'fail'; return }
    if (@($q.members) -contains $u.id) { Out-Wg ('{0} is already in {1}. Nothing changed.' -f $u.name, $q.name) 'warn'; return }
    if (-not $u.active) { Out-Wg ('{0} is not active. Refusing to add a disabled person.' -f $u.name) 'fail'; return }
    $q.members = @($q.members) + @($u.id)
    Add-WgAudit -State $s -Ticket $Ticket -Action 'queue-add' -Target $q.id -Detail $u.id
    Save-WgState $s
    Out-Wg ('Added {0} to {1}.' -f $u.name, $q.name) 'ok'
    $chk = Get-WgEligible $s $q | Where-Object { $_.UserId -eq $u.id }
    if (-not $chk.Eligible) { Out-Wg ('{0} is a member but is missing skill(s): {1}. They will NOT be alerted until the skill is added.' -f $u.name, $chk.Missing) 'warn' }
}
function Remove-WgQueueMember {
    <# .SYNOPSIS Removes a person from a queue. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Queue, [Parameter(Mandatory)][string]$User,
          [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $q = Find-WgItem $s.queues $Queue
    $u = $s.users | Where-Object { $_.id -eq $User -or $_.email -eq $User } | Select-Object -First 1
    if (-not $q -or -not $u) { Out-Wg 'Queue or person not found.' 'fail'; return }
    if (@($q.members) -notcontains $u.id) { Out-Wg ('{0} is not in {1}. Nothing changed.' -f $u.name, $q.name) 'warn'; return }
    $q.members = @($q.members | Where-Object { $_ -ne $u.id })
    Add-WgAudit -State $s -Ticket $Ticket -Action 'queue-remove' -Target $q.id -Detail $u.id
    Save-WgState $s
    Out-Wg ('Removed {0} from {1}.' -f $u.name, $q.name) 'ok'
}
function Disable-WgUser {
    <# .SYNOPSIS The leaver process: removes the person from every queue and group, then deactivates them, in one go, with an audit record. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$User, [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $u = $s.users | Where-Object { $_.id -eq $User -or $_.email -eq $User } | Select-Object -First 1
    if (-not $u) { Out-Wg ('No person called ' + $User) 'fail'; return }
    $n = 0
    foreach ($q in @($s.queues)) { if (@($q.members) -contains $u.id) { $q.members = @($q.members | Where-Object { $_ -ne $u.id }); $n++ } }
    $u.groups = @()
    $u.active = $false
    Add-WgAudit -State $s -Ticket $Ticket -Action 'leaver' -Target $u.id -Detail ('removed from {0} queues, groups cleared, deactivated' -f $n)
    Save-WgState $s
    Out-Wg ('{0}: removed from {1} queue(s), groups cleared, account deactivated.' -f $u.name, $n) 'ok'
}
function Compare-WgQueueMembership {
    <#
    .SYNOPSIS  Compares who SHOULD be in each queue (a CSV from the ticket or the manager) with who IS in it.
               The CSV has two columns: Queue (queue id) and User (email).
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$IntendedCsv, [switch]$PassThru)
    $s = Get-WgState
    $intended = @(Import-Csv -Path $IntendedCsv)
    $want = @{}
    foreach ($r in $intended) { $want[($r.Queue + '|' + $r.User.ToLower())] = $true }
    $have = @{}
    foreach ($q in @($s.queues)) {
        foreach ($uid in @($q.members)) { $u = Find-WgItem $s.users $uid; if ($u) { $have[($q.id + '|' + $u.email.ToLower())] = $true } }
    }
    $missing = @($want.Keys | Where-Object { -not $have.ContainsKey($_) } | Sort-Object)
    # only judge queues that appear in the intended list
    $queuesInList = @($intended | ForEach-Object { $_.Queue } | Select-Object -Unique)
    $extra = @($have.Keys | Where-Object { -not $want.ContainsKey($_) -and ($queuesInList -contains $_.Split('|')[0]) } | Sort-Object)
    Out-Wg 'Queue membership check' 'step'
    Out-Wg ('{0} intended pairs, {1} actual pairs (in the queues named in the list)' -f $want.Count, @($have.Keys | Where-Object { $queuesInList -contains $_.Split('|')[0] }).Count) 'ok'
    foreach ($m in $missing) { $p = $m.Split('|'); Out-Wg ('MISSING: {0} should be in {1} but is not' -f $p[1], $p[0]) 'warn' }
    foreach ($x in $extra) { $p = $x.Split('|'); Out-Wg ('EXTRA:   {0} is in {1} but should not be' -f $p[1], $p[0]) 'warn' }
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) { Out-Wg 'Membership matches the list.' 'ok' }
    else { Out-Wg ('{0} missing, {1} extra. Fix each one with a ticket. Do not edit by hand.' -f $missing.Count, $extra.Count) }
    if ($PassThru) { return [pscustomobject]@{ Missing = $missing.Count; Extra = $extra.Count } }
}

function Add-WgHoliday {
    <# .SYNOPSIS Adds a public holiday to the shared holiday schedule. Needs a ticket. Real Genesys: Schedules > the holiday schedule > add a date. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime]$Date, [Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $sch = Find-WgItem $s.schedules 'SCH-Holidays'
    $d = $Date.ToString('yyyy-MM-dd')
    if (@($sch.dates) | Where-Object { $_.date -eq $d }) { Out-Wg ($d + ' is already in the list. Nothing changed.') 'warn'; return }
    $sch.dates = @($sch.dates) + @([pscustomobject]@{ date = $d; name = $Name })
    $sch.dates = @($sch.dates | Sort-Object { $_.date })
    Add-WgAudit -State $s -Ticket $Ticket -Action 'holiday-add' -Target 'SCH-Holidays' -Detail ($d + ' ' + $Name)
    Save-WgState $s
    Out-Wg ('Added {0} {1} to SCH-Holidays. Phone and chat both use this list, so both now treat it as a holiday.' -f $d, $Name) 'ok'
}
function Add-WgUserSkill {
    <# .SYNOPSIS Gives a person a skill at a proficiency from 1 to 5. Queues that ask for the skill can then alert them. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$User, [Parameter(Mandatory)][string]$Skill, [ValidateRange(1,5)][int]$Proficiency = 3,
          [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $u = $s.users | Where-Object { $_.id -eq $User -or $_.email -eq $User } | Select-Object -First 1
    if (-not $u) { Out-Wg ('No person called ' + $User) 'fail'; return }
    if (@($s.skills) -notcontains $Skill) { Out-Wg ('No skill called {0}. Skills: {1}' -f $Skill, (@($s.skills) -join ', ')) 'fail'; return }
    $u.skills = @(@($u.skills) | Where-Object { $_.skill -ne $Skill }) + @([pscustomobject]@{ skill = $Skill; proficiency = $Proficiency })
    Add-WgAudit -State $s -Ticket $Ticket -Action 'skill-add' -Target $u.id -Detail ('{0}:{1}' -f $Skill, $Proficiency)
    Save-WgState $s
    Out-Wg ('{0} now has skill {1} at proficiency {2}.' -f $u.name, $Skill, $Proficiency) 'ok'
}
function Get-WgAudit {
    <# .SYNOPSIS Shows who changed what, when and under which ticket. Real Genesys: Audit Viewer. #>
    [CmdletBinding()] param([int]$Last = 20)
    $s = Get-WgState
    $rows = @($s.audit)
    if ($rows.Count -eq 0) { Out-Wg 'The audit log is empty. Make a change first.'; return }
    Out-WgTable ($rows | Select-Object -Last $Last | ForEach-Object { [pscustomobject]@{ When = $_.when; Ticket = $_.ticket; Action = $_.action; Target = $_.target; Detail = $_.detail } })
}

# ---------------------------------------------------------------- announcements
function Test-WgAnnouncement {
    <#
    .SYNOPSIS  Checks an announcement file BEFORE you upload it. Rules come from announcements\spec.json.
               Genesys facts (Resource Center, "Prompts overview"): WAV only, 8000 or 11025 Hz, 25 MB limit.
               Length, mono and loudness rules are this lab's own house rules.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Ticket, [switch]$PassThru)
    $spec = Get-Content -Raw -Encoding UTF8 -Path $script:SpecPath | ConvertFrom-Json
    $problems = @()
    $name = Split-Path -Leaf $Path
    Out-Wg ('Announcement check: ' + $name) 'step'
    if (-not (Test-Path $Path)) { Out-Wg 'File not found.' 'fail'; if ($PassThru) { return [pscustomobject]@{ Pass = $false; Problems = @('file not found') } }; return }
    if ($name -notmatch $spec.namePattern) { $problems += ('File name does not follow the standard <line>-<purpose>-<yyyymmdd>-v<n>.wav (purposes: ' + $spec.purposes + ')') }
    else { Out-Wg 'File name follows the standard.' 'ok' }
    if (-not (Test-WgTicket $Ticket)) { $problems += ('Ticket "{0}" is not INC/RITM/CHG plus 7 digits.' -f $Ticket) } else { Out-Wg ('Ticket {0} looks right.' -f $Ticket) 'ok' }
    $txt = [System.IO.Path]::ChangeExtension($Path, '.txt')
    if (-not (Test-Path $txt)) { $problems += ('Script text file missing. Keep the exact words next to the audio: ' + (Split-Path -Leaf $txt)) } else { Out-Wg 'Script text file is next to the audio.' 'ok' }
    $mb = (Get-Item $Path).Length / 1MB
    if ($mb -gt [double]$spec.maxMegabytes) { $problems += ('File is {0:N1} MB. Genesys allows up to {1} MB.' -f $mb, $spec.maxMegabytes) } else { Out-Wg ('Size {0:N2} MB is under the {1} MB limit.' -f $mb, $spec.maxMegabytes) 'ok' }
    if ([System.IO.Path]::GetExtension($Path).ToLower() -ne '.wav') { $problems += 'Genesys accepts WAV only. MP3 and other formats are not supported.' }
    $probe = Get-Command ffprobe -ErrorAction SilentlyContinue
    $ffm = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $probe -or -not $ffm) {
        Out-Wg 'ffprobe/ffmpeg not found, so the audio itself was NOT checked (sample rate, length, loudness). Install ffmpeg and run again.' 'warn'
    }
    else {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $raw = (& $probe.Source -v error -show_entries 'stream=sample_rate,channels,codec_name:format=duration,format_name' -of 'default=nw=1' $Path 2>&1 | ForEach-Object { "$_" })
            $info = @{}
            foreach ($l in $raw) { if ($l -match '^(\w+)=(.*)$') { $info[$Matches[1]] = $Matches[2] } }
            $vd = (& $ffm.Source -hide_banner -nostats -i $Path -af volumedetect -f null NUL 2>&1 | ForEach-Object { "$_" })
            if (($vd -join ' ') -notmatch 'max_volume') { $vd = (& $ffm.Source -hide_banner -nostats -i $Path -af volumedetect -f null - 2>&1 | ForEach-Object { "$_" }) }
        } catch { $raw = @(); $info = @{}; $vd = @() }
        $ErrorActionPreference = $prev
        if (-not $info.ContainsKey('format_name') -or $info['format_name'] -notmatch 'wav') { $problems += 'The audio is not a real WAV file (check the container).' }
        else {
            $rate = 0; [void][int]::TryParse($info['sample_rate'], [ref]$rate)
            if (@($spec.sampleRates) -notcontains $rate) { $problems += ('Sample rate is {0} Hz. Genesys needs {1} Hz.' -f $rate, (@($spec.sampleRates) -join ' or ')) } else { Out-Wg ('Sample rate {0} Hz is accepted.' -f $rate) 'ok' }
            $ch = 0; [void][int]::TryParse($info['channels'], [ref]$ch)
            if ($ch -gt [int]$spec.maxChannels) { $problems += ('{0} channels. House rule: mono.' -f $ch) } else { Out-Wg 'Mono, as the house rule asks.' 'ok' }
            $dur = 0.0; [void][double]::TryParse($info['duration'], [ref]$dur)
            if ($dur -gt [double]$spec.maxSeconds) { $problems += ('Length {0:N1} s. House rule: up to {1} s.' -f $dur, $spec.maxSeconds) } else { Out-Wg ('Length {0:N1} s.' -f $dur) 'ok' }
            $peak = $null; $mean = $null
            foreach ($l in $vd) { if ($l -match 'max_volume:\s*(-?[\d\.]+)') { $peak = [double]$Matches[1] }; if ($l -match 'mean_volume:\s*(-?[\d\.]+)') { $mean = [double]$Matches[1] } }
            if ($null -ne $peak) {
                if ($peak -gt [double]$spec.maxPeakDb) { $problems += ('Peak {0} dB is too loud and may clip. House rule: {1} dB or lower.' -f $peak, $spec.maxPeakDb) } else { Out-Wg ('Peak {0} dB: no clipping.' -f $peak) 'ok' }
                if ($mean -lt [double]$spec.minMeanDb) { $problems += ('Average {0} dB is too quiet. House rule: {1} dB or louder.' -f $mean, $spec.minMeanDb) } else { Out-Wg ('Average {0} dB: easy to hear.' -f $mean) 'ok' }
            }
        }
    }
    foreach ($p in $problems) { Out-Wg $p 'fail' }
    $pass = ($problems.Count -eq 0)
    if ($pass) { Out-Wg 'Ready to upload. Remember: after upload, republish every flow that uses this prompt.' 'ok' }
    else { Out-Wg ('{0} problem(s). Fix them, then check again.' -f $problems.Count) }
    if ($PassThru) { return [pscustomobject]@{ Pass = $pass; Problems = $problems } }
}
function Set-WgPromptAudio {
    <#
    .SYNOPSIS  Uploads a new version of a prompt (pretend). The new version is saved but NO flow plays it yet.
               Real Genesys: Architect > Prompts > the prompt > add or replace the audio.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Ticket, [string]$Text)
    if (-not (Test-WgTicket $Ticket)) { Out-Wg 'Ticket must be INC, RITM or CHG plus 7 digits.' 'fail'; return }
    $chk = Test-WgAnnouncement -Path $Path -Ticket $Ticket -PassThru
    if (-not $chk.Pass) { Out-Wg 'Upload refused: the file did not pass the check.' 'fail'; return }
    $s = Get-WgState
    $p = Find-WgItem $s.prompts $Prompt
    if (-not $p) { Out-Wg ('No prompt called ' + $Prompt) 'fail'; return }
    if (-not $Text) {
        $txt = [System.IO.Path]::ChangeExtension($Path, '.txt')
        $Text = (Get-Content -Raw -Encoding UTF8 -Path $txt).Trim()
    }
    $new = [int]$p.current + 1
    $p.versions = @($p.versions) + @([pscustomobject]@{ v = $new; file = (Split-Path -Leaf $Path); date = (Get-Date).ToString('yyyy-MM-dd'); text = $Text; ticket = $Ticket })
    $p.current = $new
    Add-WgAudit -State $s -Ticket $Ticket -Action 'prompt-upload' -Target $p.id -Detail ('v' + $new)
    Save-WgState $s
    Out-Wg ('Uploaded {0} v{1}.' -f $p.id, $new) 'ok'
    $stale = @()
    foreach ($f in @($s.flows)) { if ($f.publishedPrompts | Where-Object { $_.prompt -eq $p.id -and [int]$_.version -ne $new }) { $stale += $f.id } }
    if ($stale.Count) { Out-Wg ('Callers still hear the OLD version. Republish: ' + ($stale -join ', ')) 'warn' }
}
function Publish-WgFlow {
    <#
    .SYNOPSIS  Publishes a flow. This is the moment the flow takes a snapshot of the latest prompt versions.
               Real Genesys: Architect > open the flow > Publish. (User prompts are snapshotted at publish; system prompts are not.)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Flow, [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $f = Find-WgItem $s.flows $Flow
    if (-not $f) { Out-Wg ('No flow called ' + $Flow) 'fail'; return }
    $f.publishedVersion = [int]$f.publishedVersion + 1
    $f.draftVersion = $f.publishedVersion
    $snap = @()
    foreach ($st in @($f.steps)) {
        foreach ($k in 'prompt', 'confirmPrompt', 'openPrompt', 'closedPrompt') {
            if ($st.PSObject.Properties[$k]) {
                $p = Find-WgItem $s.prompts $st.$k
                $snap += [pscustomobject]@{ prompt = $st.$k; version = [int]$p.current }
            }
        }
    }
    $f.publishedPrompts = $snap
    Add-WgAudit -State $s -Ticket $Ticket -Action 'flow-publish' -Target $f.id -Detail ('v' + $f.publishedVersion)
    Save-WgState $s
    Out-Wg ('Published {0} as v{1}. It now plays the latest version of every prompt it uses.' -f $f.id, $f.publishedVersion) 'ok'
}
function Set-WgNotice {
    <# .SYNOPSIS Switches a line's notice slot (for example the outage notice) on or off. It is one row in a data table, so no audio upload and no republish is needed. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line, [Parameter(Mandatory)][bool]$Active,
          [Parameter(Mandatory)][ValidatePattern('^(INC|RITM|CHG)\d{7}$')][string]$Ticket)
    $s = Get-WgState
    $row = $s.dataTables.notices | Where-Object { $_.key -eq $Line } | Select-Object -First 1
    if (-not $row) { Out-Wg ('No notice slot for line ' + $Line) 'fail'; return }
    $row.active = $Active
    Add-WgAudit -State $s -Ticket $Ticket -Action 'notice-switch' -Target $Line -Detail ('active=' + $Active)
    Save-WgState $s
    Out-Wg ('Notice slot for {0} is now {1}.' -f $Line, $(if ($Active) { 'ON' } else { 'OFF' })) 'ok'
}
function Get-WgNotice {
    <# .SYNOPSIS Shows which lines currently play a notice before the greeting. #>
    [CmdletBinding()] param()
    $s = Get-WgState
    Out-WgTable ($s.dataTables.notices | ForEach-Object {
        $ln = Find-WgItem $s.lines $_.key
        [pscustomobject]@{ Line = $_.key; Name = $ln.name; NoticeOn = $_.active; Prompt = $_.message } })
}

# ---------------------------------------------------------------- the call tracer
function Trace-WgCall {
    <#
    .SYNOPSIS  Follows a pretend call from the dialled number to a queue (or a disconnect) and says what the caller hears.
               Real Genesys: you place a test call, and use the Interactions view, the flow's debug or Architect flow tester to see the path.
    .PARAMETER Number          the number dialled, e.g. +61 3 5550 0401
    .PARAMETER At              date and time of the call (Melbourne time)
    .PARAMETER Keys            keys the caller presses, in order, e.g. 1 or 9,1. No keys = the caller says nothing.
    .PARAMETER WaitMinutes     how long the queue says the wait will be. Above the threshold the callback offer plays.
    .PARAMETER AcceptCallback  the caller presses 1 to take the callback offer
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Number, [datetime]$At = (Get-Date), [string[]]$Keys = @(), [int]$WaitMinutes = 0,
          [switch]$AcceptCallback, [string]$From = '+61491570156', [string]$CallbackNumber, [switch]$PassThru)
    $s = Get-WgState
    $n = ConvertTo-WgNumber $Number
    $line = $s.lines | Where-Object { $_.number -eq $n } | Select-Object -First 1
    Out-Wg ('Call to {0} at {1}' -f (Format-WgNumber $n), $At.ToString('ddd dd MMM yyyy HH:mm')) 'step'
    $result = [pscustomobject]@{ Outcome = 'none'; Queue = ''; Callback = $false; ScheduleState = '' }
    if (-not $line) { Out-Wg 'The network says: number not in service. (No line has this number, so the call never reaches Genesys.)' 'fail'; if ($PassThru) { return $result }; return }
    $route = Find-WgItem $s.callRoutes $line.callRoute
    Out-Wg ('1. The number belongs to line {0} "{1}". Its call route is {2}.' -f $line.id, $line.name, $route.id)
    $st = Get-WgScheduleState -State $s -GroupId $route.scheduleGroup -At $At -EmergencyGroupId $(if ($route.closesForEmergency) { $route.emergencyGroup } else { '' })
    $result.ScheduleState = $st.State
    Out-Wg ('2. The route asks schedule group {0}: {1}.  ({2})' -f $route.scheduleGroup, $st.State.ToUpper(), $st.Reason)
    $flowId = $route.flows.($st.State)
    $flow = Find-WgItem $s.flows $flowId
    Out-Wg ('3. The route runs its {0} flow: {1} (published v{2}).' -f $st.State, $flow.id, $flow.publishedVersion)
    $k = 0
    $queueId = ''
    $step = 4
    foreach ($fs in @($flow.steps)) {
        switch ($fs.op) {
            'notice' {
                $row = $s.dataTables.notices | Where-Object { $_.key -eq $fs.line } | Select-Object -First 1
                if ($row -and $row.active) {
                    $ver = Get-WgSnapshotVersion $flow $row.message
                    if ($ver -eq 0) { $ver = [int](Find-WgItem $s.prompts $row.message).current }
                    Out-Wg ('{0}. Notice slot for {1} is ON, so the notice plays first (prompt {2}).' -f $step, $fs.line, $row.message); Out-Wg (Get-WgPromptText $s $row.message $ver) 'hear'
                } else { Out-Wg ('{0}. Notice slot for {1} is OFF, so nothing extra plays.' -f $step, $fs.line) }
                $step++
            }
            'play' {
                $ver = Get-WgSnapshotVersion $flow $fs.prompt
                Out-Wg ('{0}. Plays {1} (the flow''s published snapshot is v{2}).' -f $step, $fs.prompt, $ver)
                Out-Wg (Get-WgPromptText $s $fs.prompt $ver) 'hear'
                $step++
            }
            'playIfOpen' {
                $cs = Get-WgScheduleState -State $s -GroupId $fs.group -At $At -EmergencyGroupId ''
                $which = $fs.closedPrompt
                if ($cs.State -eq 'open') { $which = $fs.openPrompt }
                $ver = Get-WgSnapshotVersion $flow $which
                Out-Wg ('{0}. The flow checks schedule group {1}: {2}. So it plays {3} (snapshot v{4}).' -f $step, $fs.group, $cs.State.ToUpper(), $which, $ver)
                Out-Wg (Get-WgPromptText $s $which $ver) 'hear'
                $step++
            }
            'menu' {
                $ver = Get-WgSnapshotVersion $flow $fs.prompt
                $attempts = [int]$fs.retries + 1
                $chosen = $null
                for ($a = 1; $a -le $attempts -and -not $chosen; $a++) {
                    Out-Wg ('{0}. Menu, pass {1} of {2}: plays {3} (v{4}).' -f $step, $a, $attempts, $fs.prompt, $ver)
                    Out-Wg (Get-WgPromptText $s $fs.prompt $ver) 'hear'
                    if ($k -lt $Keys.Count) {
                        $key = $Keys[$k]; $k++
                        $opt = $fs.options.PSObject.Properties[$key]
                        if ($opt) { Out-Wg ('   Caller presses {0}: "{1}".' -f $key, $opt.Value.label); $chosen = $opt.Value.queue }
                        else { Out-Wg ('   Caller presses {0}: not a menu option. The flow says it did not understand and plays the menu again.' -f $key) 'warn' }
                    } else { Out-Wg ('   Caller says and presses nothing. After {0} seconds the menu plays again.' -f $fs.timeoutSeconds) }
                }
                if (-not $chosen) {
                    Out-Wg ('   No valid key after {0} passes, so the flow sends the call to the default: {1}.' -f $attempts, $fs.onNoInput) 'warn'
                    $chosen = $fs.onNoInput
                }
                $queueId = $chosen
                $step++
            }
            'transfer' { $queueId = $fs.queue; Out-Wg ('{0}. The flow transfers the call to queue {1}.' -f $step, $queueId); $step++ }
            'disconnect' { Out-Wg ('{0}. The flow disconnects the call.' -f $step); $result.Outcome = 'disconnected'; $step++ }
        }
        if ($queueId) { break }
        if ($fs.op -eq 'disconnect') { break }
    }
    if ($queueId) {
        $q = Find-WgItem $s.queues $queueId
        $result.Queue = $queueId; $result.Outcome = 'queued'
        Out-Wg ('{0}. The call joins queue {1} "{2}" (routing {3}, skills: {4}).' -f $step, $q.id, $q.name, $q.routingMethod, $(if (@($q.skills).Count) { (@($q.skills) -join ', ') } else { 'none' })); $step++
        $el = @(Get-WgEligible $s $q | Where-Object { $_.Eligible } | Sort-Object AvgProficiency -Descending)
        if ($el.Count -eq 0) { Out-Wg ('   NOBODY can take this call: no active member holds every skill the queue asks for. The caller would wait until they hang up.') 'fail'; $result.Outcome = 'stuck' }
        else { Out-Wg ('   Genesys would alert: {0}  (best available skills)' -f (($el | Select-Object -First 3 | ForEach-Object { '{0} (proficiency {1})' -f $_.Name, $_.AvgProficiency }) -join ', ')) }
        if ($WaitMinutes -gt 0) {
            $iq = Find-WgItem $s.flows $q.inQueueFlow
            Out-Wg ('{0}. No agent is free. The queue says the wait is about {1} minutes, so the in-queue flow {2} runs.' -f $step, $WaitMinutes, $iq.id); $step++
            foreach ($is in @($iq.steps)) {
                if ($is.op -eq 'holdMusic') { Out-Wg '   Hold music plays.' }
                if ($is.op -eq 'callbackOffer') {
                    if (-not $q.callbacksEnabled) { Out-Wg '   Callbacks are switched off for this queue, so no offer is made.' 'warn' }
                    elseif ($WaitMinutes -lt [int]$is.ewtMinutesAtLeast) { Out-Wg ('   The wait is under {0} minutes, so no callback offer is made.' -f $is.ewtMinutesAtLeast) }
                    else {
                        $ver = Get-WgSnapshotVersion $iq $is.prompt
                        Out-Wg ('   Wait is {0}+ minutes, so the callback is offered.' -f $is.ewtMinutesAtLeast)
                        Out-Wg ((Get-WgPromptText $s $is.prompt $ver) -replace '\{minutes\}', "$WaitMinutes") 'hear'
                        if ($AcceptCallback) {
                            $num = ConvertTo-WgNumber $(if ($CallbackNumber) { $CallbackNumber } else { $From })
                            if ($num -notmatch '^\+61\d{9}$') { Out-Wg ('   Callback refused: "{0}" is not a valid Australian number. The Create Callback action needs a number, and it cannot be blank.' -f $num) 'fail' }
                            else {
                                $cb = [pscustomobject]@{ id = ('CB' + ((@($s.callbacks).Count) + 1).ToString('0000')); queue = $q.id; number = $num; source = 'in-queue'; requested = $At.ToString('yyyy-MM-dd HH:mm'); status = 'Waiting' }
                                $s.callbacks = @($s.callbacks) + @($cb)
                                Save-WgState $s
                                $cv = Get-WgSnapshotVersion $iq $is.confirmPrompt
                                Out-Wg ('   Caller presses 1. A callback {0} is placed in queue {1} for {2}. The caller''s place in line is kept.' -f $cb.id, $q.id, (Format-WgNumber $num))
                                Out-Wg (Get-WgPromptText $s $is.confirmPrompt $cv) 'hear'
                                $result.Callback = $true; $result.Outcome = 'callback'
                            }
                        }
                    }
                }
            }
        }
    }
    if ($PassThru) { return $result }
}

# ---------------------------------------------------------------- callbacks, chat and the online form
function Get-WgCallback {
    <# .SYNOPSIS Lists callbacks waiting in queues. Real Genesys: they appear as callback interactions for agents, and in the Interactions view. #>
    [CmdletBinding()] param()
    $s = Get-WgState
    if (@($s.callbacks).Count -eq 0) { Out-Wg 'No callbacks waiting.'; return }
    Out-WgTable ($s.callbacks | ForEach-Object { [pscustomobject]@{ Id = $_.id; Queue = $_.queue; Number = (Format-WgNumber $_.number); Source = $_.source; Requested = $_.requested; Status = $_.status } })
}
function Request-WgCallback {
    <#
    .SYNOPSIS  A website "request a call back" form. It is the second callback type: customer-triggered, for the queue the form points at.
               Real Genesys: a callback widget on the website, or an API request that creates a callback interaction in a queue.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Queue, [Parameter(Mandatory)][string]$Number, [string]$Name = 'Web visitor', [datetime]$At = (Get-Date))
    $s = Get-WgState
    $q = Find-WgItem $s.queues $Queue
    if (-not $q) { Out-Wg ('No queue called ' + $Queue) 'fail'; return }
    if (-not $q.callbacksEnabled) { Out-Wg ('Queue {0} does not accept callbacks.' -f $q.id) 'fail'; return }
    $num = ConvertTo-WgNumber $Number
    if ($num -notmatch '^\+61\d{9}$') { Out-Wg ('"{0}" is not a valid Australian number. The form must reject it, because a callback with a wrong number is a promise nobody can keep.' -f $Number) 'fail'; return }
    $state = Get-WgScheduleState -State $s -GroupId 'SG-Phone' -At $At -EmergencyGroupId 'EG-Phone'
    $cb = [pscustomobject]@{ id = ('CB' + ((@($s.callbacks).Count) + 1).ToString('0000')); queue = $q.id; number = $num; source = 'web-form'; requested = $At.ToString('yyyy-MM-dd HH:mm'); status = 'Waiting' }
    $s.callbacks = @($s.callbacks) + @($cb)
    Save-WgState $s
    Out-Wg ('Callback {0} for {1} placed in {2}.' -f $cb.id, $Name, $q.name) 'ok'
    if ($state.State -ne 'open') { Out-Wg ('The phone team is {0} right now ({1}). The callback waits and the agent calls when the line next opens. The form should say so.' -f $state.State.ToUpper(), $state.Reason) 'warn' }
}
function Test-WgChat {
    <# .SYNOPSIS Asks what a web visitor sees if they open chat at this time. Chat has its own schedule group (8:30am to 8pm), longer than phones. #>
    [CmdletBinding()] param([Parameter(Mandatory)][datetime]$At)
    $s = Get-WgState
    $c = $s.chat
    $st = Get-WgScheduleState -State $s -GroupId $c.scheduleGroup -At $At -EmergencyGroupId ''
    Out-Wg ('Chat at {0}: {1}' -f $At.ToString('ddd dd MMM HH:mm'), $st.State.ToUpper()) 'step'
    Out-Wg ('  Why: ' + $st.Reason)
    $ph = Get-WgScheduleState -State $s -GroupId 'SG-Phone' -At $At -EmergencyGroupId 'EG-Phone'
    Out-Wg ('  (For comparison, the phone line is {0} at the same time.)' -f $ph.State.ToUpper())
    if ($st.State -eq 'open') {
        $q = Find-WgItem $s.queues $c.queue
        $el = @(Get-WgEligible $s $q | Where-Object { $_.Eligible })
        Out-Wg ('  The visitor sees: "{0}"  ({1} agent(s) can take chat in {2})' -f $c.greeting, $el.Count, $q.id)
    } else { Out-Wg ('  The visitor sees: "{0}"' -f $c.closedMessage) }
}
function Get-WgEnquiryDue {
    <# .SYNOPSIS Works out the reply window for the online enquiry form: 3 to 5 BUSINESS days, skipping weekends and public holidays. #>
    [CmdletBinding()] param([Parameter(Mandatory)][datetime]$Submitted)
    $s = Get-WgState
    $hol = @(); foreach ($sch in @($s.schedules | Where-Object { $_.type -eq 'dates' })) { foreach ($d in @($sch.dates)) { $hol += $d.date } }
    $min = [int]$s.enquiryForm.replyBusinessDaysMin; $max = [int]$s.enquiryForm.replyBusinessDaysMax
    $d = $Submitted.Date; $count = 0; $dueMin = $null; $dueMax = $null
    while ($count -lt $max) {
        $d = $d.AddDays(1)
        if ($d.DayOfWeek -eq 'Saturday' -or $d.DayOfWeek -eq 'Sunday') { continue }
        if ($hol -contains $d.ToString('yyyy-MM-dd')) { continue }
        $count++
        if ($count -eq $min) { $dueMin = $d }
        if ($count -eq $max) { $dueMax = $d }
    }
    Out-Wg ('Enquiry submitted {0}.' -f $Submitted.ToString('ddd dd MMM yyyy')) 'step'
    Out-Wg ('  Reply promised between {0} and {1} ({2} to {3} business days, weekends and public holidays skipped).' -f $dueMin.ToString('ddd dd MMM'), $dueMax.ToString('ddd dd MMM'), $min, $max)
    Out-Wg ('  Handled by: ' + $s.enquiryForm.handledBy)
}

# ---------------------------------------------------------------- documentation
function Export-WgCallMap {
    <#
    .SYNOPSIS  Writes a plain-text map of every line: number, hours, menu and queues. Run it after every change so the document cannot drift from the system.
    #>
    [CmdletBinding()] param([string]$Path)
    $s = Get-WgState
    $out = @('# Call map (generated ' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + ')', '', 'Pretend company. Do not edit by hand: run Export-WgCallMap.', '')
    foreach ($l in @($s.lines)) {
        $r = Find-WgItem $s.callRoutes $l.callRoute
        $f = Find-WgItem $s.flows $r.flows.open
        $out += ('## {0} - {1}  ({2})' -f $l.id, $l.name, (Format-WgNumber $l.number))
        $out += ('- Hours group: {0}.  Emergency group: {1}.  Open flow: {2} v{3}.' -f $r.scheduleGroup, $r.emergencyGroup, $f.id, $f.publishedVersion)
        $notice = $s.dataTables.notices | Where-Object { $_.key -eq $l.id } | Select-Object -First 1
        $out += ('- Notice slot: ' + $(if ($notice.active) { 'ON' } else { 'off' }))
        foreach ($st in @($f.steps)) {
            if ($st.op -eq 'menu') { foreach ($p in $st.options.PSObject.Properties) { $out += ('- Press {0}: {1} -> {2}' -f $p.Name, $p.Value.label, $p.Value.queue) }; $out += ('- No input after retries: ' + $st.onNoInput) }
            if ($st.op -eq 'transfer') { $out += ('- Goes straight to: ' + $st.queue) }
        }
        $out += ''
    }
    if ($Path) { $out | Set-Content -Encoding UTF8 -Path $Path; Out-Wg ('Call map written to ' + $Path) 'ok' } else { $out | ForEach-Object { Write-Host $_ } }
}

Export-ModuleMember -Function Reset-WgOrg, Get-WgLine, Get-WgCallRoute, Get-WgFlow, Get-WgPrompt, Get-WgPromptUsage, Get-WgScheduleGroup,
    Test-WgSchedule, Test-WgHolidayCoverage, Get-WgEmergencyGroup, Set-WgEmergencyGroup, Get-WgQueue, Get-WgUser, Get-WgRole,
    Add-WgQueueMember, Remove-WgQueueMember, Disable-WgUser, Compare-WgQueueMembership, Get-WgAudit, Test-WgAnnouncement, Set-WgPromptAudio,
    Publish-WgFlow, Add-WgHoliday, Add-WgUserSkill, Set-WgNotice, Get-WgNotice, Trace-WgCall, Get-WgCallback, Request-WgCallback, Test-WgChat, Get-WgEnquiryDue, Export-WgCallMap
