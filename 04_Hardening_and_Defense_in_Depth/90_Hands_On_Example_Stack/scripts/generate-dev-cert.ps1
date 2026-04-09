$root = Split-Path -Parent $PSScriptRoot
$certDir = Join-Path $root "certs\\runtime"

New-Item -ItemType Directory -Force -Path $certDir | Out-Null

openssl req -x509 -nodes -newkey rsa:2048 -days 365 `
  -keyout (Join-Path $certDir "privkey.pem") `
  -out (Join-Path $certDir "fullchain.pem") `
  -subj "/CN=localhost" `
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

Write-Host "Created training certificate in certs/runtime/"
