[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$openssl = Get-Command openssl -ErrorAction Stop
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$materialDirectory = Join-Path $projectRoot 'entry\src\main\resources\rawfile\demo_tls'
New-Item -ItemType Directory -Force -Path $materialDirectory | Out-Null

$certificatePath = Join-Path $materialDirectory 'server-cert.pem'
$privateKeyPath = Join-Path $materialDirectory 'server-key.pem'
$caPath = Join-Path $materialDirectory 'ca-cert.pem'

& $openssl.Source req -x509 -newkey rsa:2048 -sha256 -days 7 -nodes `
  -subj '/CN=SemaLink Demo TLS' -keyout $privateKeyPath -out $certificatePath
if ($LASTEXITCODE -ne 0) { throw 'OpenSSL failed to generate demo TLS material.' }
Copy-Item -LiteralPath $certificatePath -Destination $caPath -Force
Write-Host "Generated demo TLS material in $materialDirectory"
