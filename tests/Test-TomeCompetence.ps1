# Offline reference checks. Engine metadata and Papyrus execution require the runtime checklist.
$ErrorActionPreference = 'Stop'

function Limit([double]$value, [double]$low, [double]$high) {
    [Math]::Min($high, [Math]::Max($low, $value))
}

function Get-Tier([int]$minimumSkill) {
    if ($minimumSkill -lt 0 -or $minimumSkill -gt 100 -or $minimumSkill % 25 -ne 0) {
        return -1
    }
    [int]($minimumSkill / 25)
}

function Assert-Equal($actual, $expected, [string]$label) {
    if ($actual -ne $expected) {
        throw "$label expected $expected, got $actual"
    }
}

$minimumSkills = 0, 25, 50, 75, 100
for ($tier = 0; $tier -lt $minimumSkills.Count; $tier++) {
    Assert-Equal (Get-Tier $minimumSkills[$tier]) $tier "Canonical tier $tier"
}
foreach ($skill in -25, -1, 1, 24, 26, 90, 101, 125) {
    Assert-Equal (Get-Tier $skill) -1 "Unsupported minimum skill $skill"
}

$cases = @(
    @{ Magicka = 100; Skill = 15; Tier = 0; Contribution = 0; Score = 15; Target = 15; Margin = 0; Safe = $true; Severity = 0 }
    @{ Magicka = 100; Skill = 15; Tier = 1; Contribution = 0; Score = 15; Target = 35; Margin = -20; Safe = $false; Severity = 0.5 }
    @{ Magicka = 250; Skill = 15; Tier = 2; Contribution = 30; Score = 45; Target = 55; Margin = -10; Safe = $false; Severity = 0.25 }
    @{ Magicka = 75; Skill = 100; Tier = 4; Contribution = -5; Score = 95; Target = 95; Margin = 0; Safe = $true; Severity = 0 }
    @{ Magicka = 0; Skill = -5; Tier = 4; Contribution = -10; Score = -10; Target = 95; Margin = -105; Safe = $false; Severity = 1 }
    @{ Magicka = 500; Skill = 150; Tier = 4; Contribution = 30; Score = 130; Target = 95; Margin = 35; Safe = $true; Severity = 0 }
)
foreach ($case in $cases) {
    $label = "Magicka $($case.Magicka), skill $($case.Skill), tier $($case.Tier)"
    $contribution = Limit (($case.Magicka - 100) / 5) -10 30
    $score = (Limit $case.Skill 0 100) + $contribution
    $target = 15 + 20 * $case.Tier
    $margin = $score - $target
    Assert-Equal $contribution $case.Contribution "$label contribution"
    Assert-Equal $score $case.Score "$label score"
    Assert-Equal $target $case.Target "$label target"
    Assert-Equal $margin $case.Margin "$label margin"
    Assert-Equal ($margin -ge 0) $case.Safe "$label safe"
    Assert-Equal (Limit (-$margin / 40) 0 1) $case.Severity "$label severity"
}
Write-Output '13 tier cases and 6 competence cases passed.'
