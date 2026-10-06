# Copy a finished build (build\bin) into bin\. The CUDA runtime DLLs (cublas, cudart, nvJitLink, nvvm) are not
# built; they stay in bin\ from the first install. Prints the server's version afterwards.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$From = Join-Path $Root 'build\bin'
$To = Join-Path $Root 'bin'
New-Item -ItemType Directory -Force $To | Out-Null
Get-ChildItem $From -Include *.exe, *.dll -Recurse | ForEach-Object { Copy-Item $_.FullName $To -Force }
# (no 2>&1: Windows PowerShell 5.1 wraps a native program's stderr lines in error records)
& (Join-Path $To 'llama-server.exe') --version
