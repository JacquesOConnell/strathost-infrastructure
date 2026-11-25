param(
    [string]$TerraformPath = 'terraform',
    [switch]$Initialize,
    [bool]$IncludeCloudflare = $true
)

# Local schemas and mocked plans only. This script never runs a live plan or apply.
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$terraformExecutable = (Get-Command $TerraformPath -ErrorAction Stop).Source
$originalLocation = Get-Location
try {
    Set-Location -LiteralPath $repositoryRoot
    & $terraformExecutable fmt -check -recursive
    if ($LASTEXITCODE -ne 0) { throw 'Terraform formatting failed.' }

    $directories = @(
        'bootstrap', 'modules/networking', 'modules/security', 'modules/encryption',
        'modules/iam', 'modules/storage', 'modules/database', 'modules/ec2',
        'modules/load-balancing', 'modules/dns', 'modules/backup', 'modules/monitoring', '.'
    )
    if ($IncludeCloudflare) { $directories += @('cloudflare', 'modules/cloudflare') }

    foreach ($directory in $directories) {
        Write-Host "Checking $directory"
        if ($Initialize) {
            & $terraformExecutable "-chdir=$directory" init -backend=false -input=false -no-color
            if ($LASTEXITCODE -ne 0) { throw "Initialization failed: $directory" }
        }
        & $terraformExecutable "-chdir=$directory" validate -no-color
        if ($LASTEXITCODE -ne 0) { throw "Schema validation failed: $directory" }
        if (Test-Path -LiteralPath (Join-Path $directory 'tests')) {
            & $terraformExecutable "-chdir=$directory" test -no-color
            if ($LASTEXITCODE -ne 0) { throw "Mock tests failed: $directory" }
        }
    }
}
finally {
    Set-Location -LiteralPath $originalLocation
}
