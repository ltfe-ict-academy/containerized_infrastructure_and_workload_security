$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "secrets\\runtime"
$examples = Join-Path $root "secrets\\examples"

New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$names = @(
    "postgres_password",
    "app_db_password",
    "redis_password",
    "grafana_admin_password"
)

foreach ($name in $names) {
    $src = Join-Path $examples "$name.txt"
    $dst = Join-Path $runtime "$name.txt"
    if (-not (Test-Path $dst)) {
        Copy-Item $src $dst
    }
}

Write-Host "Prepared training secrets in secrets/runtime/"
