# Render docs/img/cards.html (speed, quality, agentic) to 2400x1350 PNGs with headless Edge or Chrome.
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot; $Html = Join-Path $Here 'cards.html'
$Browser = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Browser) { throw 'Edge or Chrome is needed for headless rendering' }
$ErrorActionPreference = 'Continue'
foreach ($c in 'speed', 'quality', 'agentic') {
    $png = Join-Path $Here "$c.png"
    & $Browser --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,675 --virtual-time-budget=4000 "--screenshot=$png" ("file:///" + $Html.Replace([char]92, [char]47) + "?c=$c") 2>$null | Out-Null
    Write-Host ("{0,-8} {1,6:N0} KB" -f $c, ((Get-Item $png).Length / 1KB))
}
