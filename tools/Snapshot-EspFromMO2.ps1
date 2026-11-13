$ErrorActionPreference = 'Stop'

function Get-Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$repo = Split-Path -Parent $PSScriptRoot
$config = Get-Content -Raw -LiteralPath (Join-Path $repo '.vscode/mo2-deploy.json') | ConvertFrom-Json
$modPath = $config.destination
if ($modPath -isnot [string] -or $modPath -notmatch '^[A-Za-z]:[\\/]') {
    throw 'Set destination to the absolute drive path of the MO2 mod folder.'
}
$mod = Get-Item -LiteralPath ([IO.Path]::GetFullPath($modPath)) -Force
if (!$mod.PSIsContainer -or !$mod.Parent) {
    throw 'The MO2 mod directory must exist below the drive root.'
}
foreach ($path in @($mod.FullName, $repo)) {
    for ($dir = Get-Item -LiteralPath $path -Force; $dir; $dir = $dir.Parent) {
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked directory is unsupported: $($dir.FullName)"
        }
    }
}
$comparison = [StringComparison]::OrdinalIgnoreCase
if ($mod.FullName.Equals($repo, $comparison) -or
    $mod.FullName.StartsWith("$repo\", $comparison) -or
    $repo.StartsWith("$($mod.FullName)\", $comparison)) {
    throw 'The repository and MO2 folders must be separate.'
}

$espFile = $config.espFile
if ($null -eq $espFile) { $espFile = 'UntamedTomes.esp' }
if ($espFile -isnot [string] -or $espFile -notin @('UntamedTomes.esp', 'Untamed Tomes.esp')) {
    throw 'Set espFile to UntamedTomes.esp or Untamed Tomes.esp to match the MO2 filename.'
}
$source = Join-Path $mod.FullName $espFile
$destination = Join-Path $repo 'UntamedTomes.esp'
Write-Host "Source:      $source"
Write-Host "Destination: $destination"

$plugin = Get-Item -LiteralPath $source -Force
if ($plugin.PSIsContainer -or !$plugin.Length -or ($plugin.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "Expected a nonempty, ordinary ESP file at $source"
}
$existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
if ($existing -and ($existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
    throw "Expected an ordinary file at $destination"
}

$sourceHash = Get-Hash $source
Write-Host "MO2 SHA-256:        $sourceHash"
if ($existing) {
    $existingHash = Get-Hash $destination
    Write-Host "Repository SHA-256: $existingHash"
    if ($existingHash -eq $sourceHash) {
        Write-Host 'The snapshot already matches.'
        return
    }
    if ((Read-Host 'The snapshots differ. Type SNAPSHOT to replace the repository copy') -cne 'SNAPSHOT') {
        throw 'Snapshot cancelled.'
    }
}

$staged = Join-Path $repo ('.esp-snapshot-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::Copy($source, $staged)
    if ((Get-Hash $staged) -ne $sourceHash -or (Get-Hash $source) -ne $sourceHash) {
        throw 'The MO2 ESP changed while taking the snapshot. Save and close the plugin, then retry.'
    }
    if ($existing) {
        if ((Get-Hash $destination) -ne $existingHash) {
            throw 'The repository ESP changed after confirmation. Retry the snapshot.'
        }
        [IO.File]::Replace($staged, $destination, [NullString]::Value)
    } else {
        [IO.File]::Move($staged, $destination)
    }
    $savedHash = Get-Hash $destination
    if ($savedHash -ne $sourceHash) {
        throw 'The repository snapshot failed SHA-256 verification.'
    }
    Write-Host "Verified SHA-256:   $savedHash"
} finally {
    if (Test-Path -LiteralPath $staged -PathType Leaf) {
        Remove-Item -LiteralPath $staged
    }
}
