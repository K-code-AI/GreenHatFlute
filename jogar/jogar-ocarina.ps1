# Abre o Ocarina Recomp.
$env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"
$env:TOTK_GPL = "0"   # bindless set 2 + an allocated vertex set in an independent layout loses the device
$env:TOTK_ASYNC_PREEMPT = "0"
$env:DKB_SKIP_CS = "3bdfe449de832903,909139c13b510f1f,753f8ab880fe7923,c968ad44272dcbb4,785a41d2df6dc095,db8c39bdb420e068,dec1feb3c7fa967a,09931d0c57c6b67f,13cab66ee383c4f4,3f6f2b1d671badcd"   # the game's upscaler: giant shaders that take many minutes to compile
if (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }) { $env:TOTK_GPU_NAME = "NVIDIA" }
$raiz = Split-Path $PSScriptRoot -Parent
$env:TOTK_PROFILE_DIR = Join-Path $raiz "perfil"
Set-Location (Join-Path $raiz "build\oot111")
$extras = if ($args.Count) { @{ ArgumentList = $args } } else { @{} }
Start-Process .\ocarina.exe @extras -RedirectStandardOutput (Join-Path $raiz "ultima-partida.log") -RedirectStandardError (Join-Path $raiz "ultima-partida-erros.log")
