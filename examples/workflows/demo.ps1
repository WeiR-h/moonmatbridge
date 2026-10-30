param([string]$Executable = "", [string]$OutputDirectory = "")
$ErrorActionPreference = "Stop"
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
if (-not $Executable) {
    $Executable = Join-Path $project "moonmat.exe"
    if (-not (Test-Path -LiteralPath $Executable)) { $Executable = Join-Path $project "dist/moonmat.exe" }
}
$Executable = (Resolve-Path -LiteralPath $Executable).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project ("verification/local/workflow-demo-" + [Guid]::NewGuid().ToString("N")) }
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory must be new: $OutputDirectory" }
$output = [IO.Path]::GetFullPath($OutputDirectory)
$null = [IO.Directory]::CreateDirectory($output)
$receipts = [Collections.Generic.List[object]]::new()

function Invoke-Moon([string[]]$Arguments, [int]$ExpectedExit = 0) {
    $ErrorActionPreference = "Continue"
    $lines = & $Executable @Arguments 2>&1
    $actualExit = $LASTEXITCODE
    $text = ($lines | ForEach-Object { $_.ToString() }) -join "`n"
    if ($actualExit -ne $ExpectedExit) { throw "Command failed ($actualExit): $($Arguments -join ' ')`n$text" }
    $value = $text | ConvertFrom-Json -ErrorAction Stop
    $receipts.Add([pscustomobject]@{ arguments = $Arguments; expected_exit = $ExpectedExit; actual_exit = $actualExit; response = $value })
    Write-Host ("PASS exit {0}: {1}" -f $actualExit, $Arguments[0])
    return $value
}
function Destination([string]$Name) { return Join-Path $output $Name }
function File-Digest([string]$Path) {
    $sourceStream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($sourceStream)).Replace("-", "").ToLowerInvariant() }
    finally { $hasher.Dispose(); $sourceStream.Dispose() }
}

Write-Host "1/3 Mixed experimental archive"
$mixed = Join-Path $project "examples/mixed/research-mixed.mat"
$roots = Invoke-Moon @("roots", $mixed)
if ($roots.roots.Count -ne 13) { throw "Mixed root directory check failed" }
$roots.roots | Select-Object name, class_id, shape | Format-Table | Out-Host
$allClasses = Invoke-Moon @("roots", (Join-Path $PSScriptRoot "all-base-classes.mat"))
if (@($allClasses.roots.class_id | Sort-Object -Unique).Count -ne 15) { throw "Base class coverage check failed" }
$null = Invoke-Moon @("compress", $mixed, (Destination "archive-compressed.mat"))
$null = Invoke-Moon @("roundtrip", (Destination "archive-compressed.mat"), (Destination "archive-restored.mat"))
$null = Invoke-Moon @("roundtrip", (Join-Path $PSScriptRoot "all-base-classes.mat"), (Destination "all-base-classes.mat"))

$null = Invoke-Moon @("snapshot-tree", $mixed, (Destination "mixed-tree.json"))
$null = Invoke-Moon @("restore-tree", (Destination "mixed-tree.json"), (Destination "mixed-tree-restored.mat"))
$null = Invoke-Moon @("diff-tree", $mixed, (Destination "mixed-tree-restored.mat"), (Destination "mixed-tree-diff.json"))

Write-Host "2/3 Large sparse simulation exchange"
$sparse = Join-Path $PSScriptRoot "sparse-system.mat"
$null = Invoke-Moon @("roots", $sparse)
$null = Invoke-Moon @("select", $sparse, (Destination "system.mat"), "system")
$null = Invoke-Moon @("snapshot", (Destination "system.mat"), (Destination "system-snapshot.json"))
$null = Invoke-Moon @("restore", (Destination "system-snapshot.json"), (Destination "system-restored.mat"))
$null = Invoke-Moon @("diff", (Destination "system.mat"), (Destination "system-restored.mat"))
$denied = Invoke-Moon @("densify", (Destination "system.mat"), "system", (Destination "too-large.mat")) 1
if ($denied.code -ne "element-limit" -or (Test-Path -LiteralPath (Destination "too-large.mat"))) { throw "Densify safety check failed" }

Write-Host "3/3 NumPy interchange, transforms and exact difference"
$null = Invoke-Moon @("from-npy", (Join-Path $PSScriptRoot "signal.npy"), "signal", (Destination "signal.mat"))
$null = Invoke-Moon @("transform", (Destination "signal.mat"), (Join-Path $PSScriptRoot "transform-plan.json"), (Destination "transformed.mat"))
$null = Invoke-Moon @("npy", (Destination "transformed.mat"), "signal", (Destination "transformed.npy"))
$null = Invoke-Moon @("roundtrip", (Destination "transformed.mat"), (Destination "transformed-copy.mat"))
$equal = Invoke-Moon @("diff", (Destination "transformed.mat"), (Destination "transformed-copy.mat"))
if (-not $equal.content_equal) { throw "Equal diff failed" }
$null = Invoke-Moon @("from-npy", (Join-Path $PSScriptRoot "changed-signal.npy"), "signal", (Destination "changed.mat"))
$null = Invoke-Moon @("diff", (Destination "transformed.mat"), (Destination "changed.mat"), (Destination "changed-report.json")) 2
$changed = Get-Content -LiteralPath (Destination "changed-report.json") -Raw | ConvertFrom-Json
if ($changed.content_equal -or $changed.variables[0].samples[0].coordinates[0] -ne 0 -or $changed.variables[0].samples[0].coordinates[1] -ne 0) { throw "Changed diff coordinates failed" }
[IO.File]::WriteAllText((Destination "tolerance.json"), '{"atol":0.25,"rtol":0,"equal_nan":true}', [Text.UTF8Encoding]::new($false))
$null = Invoke-Moon @("diff-tree-close", (Destination "transformed.mat"), (Destination "changed.mat"), (Destination "close-report.json"), (Destination "tolerance.json"))
$close = Get-Content -LiteralPath (Destination "close-report.json") -Raw | ConvertFrom-Json
if (-not $close.within_tolerance -or $close.exact_equal) { throw "Tolerance comparison failed" }
$missing = Invoke-Moon @("npy", (Destination "transformed.mat"), "missing", (Destination "missing.npy")) 1
if ($missing.code -ne "missing-variable" -or (Test-Path -LiteralPath (Destination "missing.npy"))) { throw "Missing export check failed" }

$hashes = @(Get-ChildItem -LiteralPath $output -File | ForEach-Object { [pscustomobject]@{ file = $_.Name; sha256 = (File-Digest $_.FullName) } })
$receipt = [pscustomobject]@{ status = "passed"; executable_sha256 = (File-Digest $Executable); commands = $receipts; files = $hashes }
$receipt | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Destination "demo-receipt.json") -Encoding UTF8
Write-Host "All three workflows passed. Results: $output"
