# Start-Lab.ps1  -  loads the pretend Genesys org so you can practise. No sign-in, no network.
#   .\Start-Lab.ps1
# If Windows blocks the script, run these two lines once in this window, then try again:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   Get-ChildItem -Recurse | Unblock-File
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path (Join-Path $here 'tools') 'Wattle.psm1') -Force
Set-Location $here
Write-Host ''
Write-Host 'Pretend Genesys org loaded. Nothing here talks to a real system.' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Try these first:'
Write-Host '  Get-WgLine                                   the 7 phone numbers'
Write-Host '  Trace-WgCall -Number "+61 3 5550 0401" -At "2026-11-16 10:15" -Keys 1'
Write-Host '  Get-Command -Module Wattle                   every command you can use'
Write-Host '  Get-Help Trace-WgCall -Detail                help for any command'
Write-Host '  Reset-WgOrg                                  start again from the beginning'
Write-Host ''
