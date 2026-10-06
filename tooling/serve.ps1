# Test launcher: starts bin\llama-server.exe HIDDEN (no visible console), its log in logs\<label>.log (the server's
# own --log-file; a stderr pipe redirected by Start-Process loses its reader when this script exits and the server
# blocks once the pipe fills), PID to logs\<label>.pid, and returns at once. tooling\stop.ps1 stops it. Everything
# comes from the environment so bash drivers can start variants without quoting arrays:
#   MIRAI_LABEL  (test)      log/pid name
#   MIRAI_CTX    (65536)     context window
#   MIRAI_EXTRA  ('')        extra llama-server flags, space separated
#   MIRAI_PORT   (18081)     listen port on 127.0.0.1
#   MIRAI_MODEL  (models\Qwen3.8-27B-S-mirai.gguf)
#   MIRAI_SERVER_ENV ('')    extra environment for the server, e.g. "GGML_CUDA_OP_TIMING=1 GGML_CUDA_DISABLE_GRAPHS=1"
# Base flags mirror the model-fork profile run (templates\bonsai-template.jinja, reasoning_effort medium, q8_0 KV,
# -b 1024 -ub 1024, model-card sampling) so every variant is a like-for-like comparison with receipts/mirai-port.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Label = if ($env:MIRAI_LABEL) { $env:MIRAI_LABEL } else { 'test' }
$Ctx = if ($env:MIRAI_CTX) { [int]$env:MIRAI_CTX } else { 65536 }
$Port = if ($env:MIRAI_PORT) { [int]$env:MIRAI_PORT } else { 18081 }
$Model = if ($env:MIRAI_MODEL) { $env:MIRAI_MODEL } else { Join-Path $Root 'models\Qwen3.8-27B-S-mirai.gguf' }
if (-not [IO.Path]::IsPathRooted($Model)) { $Model = Join-Path $Root $Model }
if (-not (Test-Path $Model)) { throw "model not found: $Model" }
[string[]]$Extra = if ($env:MIRAI_EXTRA) { ($env:MIRAI_EXTRA -split ' ') | Where-Object { $_ -ne '' } } else { @() }
$Logs = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force $Logs | Out-Null

$ApiKeyFile = Join-Path $Root 'artifacts\api_key.txt'
if (-not (Test-Path $ApiKeyFile)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $ApiKeyFile) | Out-Null
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    Set-Content -Path $ApiKeyFile -Value (-join ($bytes | ForEach-Object { $_.ToString('x2') })) -NoNewline
}
$Key = (Get-Content -Path $ApiKeyFile -Raw).Trim()

$env:GGML_CUDA_BATCH_INVARIANT = '1'
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"reasoning_effort":"medium"}'
if ($env:MIRAI_SERVER_ENV) {
    foreach ($kv in ($env:MIRAI_SERVER_ENV -split ' ')) {
        if ($kv -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] }
    }
}
[string[]]$ServerArgs = @(
    '-m', $Model,
    '--chat-template-file', (Join-Path $Root 'templates\bonsai-template.jinja'), '--jinja',
    '-fa', 'on', '-c', "$Ctx", '-np', '1', '-b', '1024', '-ub', '1024', '-ngl', '99', '-ctk', 'q8_0', '-ctv', 'q8_0',
    '--host', '127.0.0.1', '--port', "$Port", '--alias', 'mirai-s-27b', '--metrics', '--api-key', $Key,
    '--temp', '1.0', '--top-p', '0.95', '--top-k', '20'
)
$Log = Join-Path $Logs "$Label.log"
Remove-Item $Log -ErrorAction SilentlyContinue
$ServerArgs += @('--log-file', $Log)
$ServerArgs += $Extra
# MIRAI_CAPTURE_STDERR=1: run under cmd.exe so raw stderr (ggml prints that bypass the log callback) lands in
# logs\<label>.stderr; cmd stays alive as the parent, so the file handle never loses its reader.
# MIRAI_BIN (e.g. build\bin) runs a freshly built tree without touching bin\; the CUDA runtime DLLs stay on PATH via bin\.
$BinDir = if ($env:MIRAI_BIN) { Join-Path $Root $env:MIRAI_BIN } else { Join-Path $Root 'bin' }
if ($env:MIRAI_BIN) { $env:PATH = (Join-Path $Root 'bin') + ';' + $env:PATH }
$Exe = Join-Path $BinDir 'llama-server.exe'
if ($env:MIRAI_CAPTURE_STDERR -eq '1') {
    $StdErr = Join-Path $Logs "$Label.stderr"
    Remove-Item $StdErr -ErrorAction SilentlyContinue
    # no quotes anywhere (no path here has spaces): cmd /c strips a leading and the last quote when a line has
    # more than two quotes or a redirect, which mangles a quoted command
    $CmdLine = $Exe + ' ' + ($ServerArgs -join ' ') + ' 2>> ' + $StdErr
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CmdLine) -WorkingDirectory $BinDir -WindowStyle Hidden -PassThru
} else {
    $p = Start-Process -FilePath $Exe -ArgumentList $ServerArgs -WorkingDirectory $BinDir `
        -WindowStyle Hidden -PassThru
}
Set-Content -Path (Join-Path $Logs "$Label.pid") -Value $p.Id -NoNewline
Write-Output "$Label pid=$($p.Id) port=$Port ctx=$Ctx extra=[$($Extra -join ' ')] log=$Log"
