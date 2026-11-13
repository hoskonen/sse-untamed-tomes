$ErrorActionPreference = 'Stop'

function Assert-OrdinaryPath($Item) {
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Deployment does not support linked paths: $($Item.FullName)"
    }
}

$repo = Split-Path -Parent $PSScriptRoot
$config = Join-Path $repo '.vscode/mo2-deploy.json'
if (!(Test-Path -LiteralPath $config -PathType Leaf)) {
    throw "Create the local deployment configuration at $config. See README.md."
}

$destination = (Get-Content -Raw -LiteralPath $config | ConvertFrom-Json).destination
if ($destination -isnot [string] -or $destination -notmatch '^[A-Za-z]:[\\/]') {
    throw 'Set destination to the absolute drive path of an existing MO2 mod folder.'
}

$mod = Get-Item -LiteralPath ([IO.Path]::GetFullPath($destination)) -Force
$comparison = [StringComparison]::OrdinalIgnoreCase
if (!$mod.PSIsContainer -or !$mod.Parent) {
    throw 'The destination must be an existing mod folder, below the drive root.'
}
if ($mod.FullName.Equals($repo, $comparison) -or
    $mod.FullName.StartsWith("$repo\", $comparison) -or
    $repo.StartsWith("$($mod.FullName)\", $comparison)) {
    throw 'The repository and deployment folders must be separate.'
}
for ($folder = $mod; $folder; $folder = $folder.Parent) {
    Assert-OrdinaryPath $folder
}

$sourceScripts = Get-Item -LiteralPath (Join-Path $repo 'Scripts') -Force
if (!$sourceScripts.PSIsContainer) {
    throw "Expected a source directory at $($sourceScripts.FullName)"
}
Assert-OrdinaryPath $sourceScripts
$targetScripts = Join-Path $mod.FullName 'Scripts'
$targetFolder = Get-Item -LiteralPath $targetScripts -Force -ErrorAction SilentlyContinue
if ($targetFolder) {
    Assert-OrdinaryPath $targetFolder
    if (!$targetFolder.PSIsContainer) {
        throw "Expected a directory at $targetScripts"
    }
}

# Validate both files and their targets before writing anything.
$names = 'UT_PlayerMonitor.pex', 'UT_MCM.pex'
foreach ($name in $names) {
    $source = Get-Item -LiteralPath (Join-Path $sourceScripts.FullName $name) -Force -ErrorAction SilentlyContinue
    if (!$source -or $source.PSIsContainer -or !$source.Length) {
        throw "Missing or empty compiled script: $name. Compile both scripts first."
    }
    Assert-OrdinaryPath $source

    $target = Get-Item -LiteralPath (Join-Path $targetScripts $name) -Force -ErrorAction SilentlyContinue
    if ($target) {
        Assert-OrdinaryPath $target
        if ($target.PSIsContainer -or $target.IsReadOnly) {
            throw "Expected a writable PEX file at $($target.FullName)"
        }
    }
}

if (!$targetFolder) {
    [IO.Directory]::CreateDirectory($targetScripts) | Out-Null
}
foreach ($name in $names) {
    $target = Join-Path $targetScripts $name
    Copy-Item -LiteralPath (Join-Path $sourceScripts.FullName $name) -Destination $target
    Write-Host "Deployed $target"
}
