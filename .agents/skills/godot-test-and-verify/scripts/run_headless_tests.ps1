<#
.SYNOPSIS
    Runs the headless Godot test suite for D:\My game\project and validates output cleanliness.
.PARAMETER ProjectPath
    Path to the Godot project directory containing project.godot.
.PARAMETER TestScene
    Godot resource path to the test runner scene.
.PARAMETER GodotPath
    Optional explicit path to the Godot executable. Auto-resolved if omitted.
.PARAMETER Filter
    Optional regex/substring filter for displaying matching suite lines (full runner still executes).
.PARAMETER CheckUids
    Also checks .uid sidecar files for project/src and res:// references in .tscn/.tres files.
.PARAMETER VerboseLog
    Prints the complete unfiltered Godot stdout/stderr log.
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = "D:\My game\project",
    [string]$TestScene = "res://tests/test_runner.tscn",
    [string]$GodotPath = "",
    [string]$Filter = "",
    [switch]$CheckUids,
    [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-GodotExecutable {
    param([string]$ExplicitPath)

    if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    if ($env:GODOT_PATH -and (Test-Path -LiteralPath $env:GODOT_PATH)) {
        return (Resolve-Path -LiteralPath $env:GODOT_PATH).Path
    }

    foreach ($cmdName in @("godot", "godot4")) {
        $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return $cmd.Source
        }
    }

    $mcpConfigPath = Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"
    if (Test-Path -LiteralPath $mcpConfigPath) {
        try {
            $mcpJson = Get-Content -LiteralPath $mcpConfigPath -Raw | ConvertFrom-Json
            $cfgGodot = $mcpJson.mcpServers.godot.env.GODOT_PATH
            if ($cfgGodot -and (Test-Path -LiteralPath $cfgGodot)) {
                return (Resolve-Path -LiteralPath $cfgGodot).Path
            }
        } catch {
            # Ignore malformed optional config and continue fallback search
        }
    }

    $fallbackCandidates = @(
        "D:\progs\godot\Godot_v4.7.2-stable_win64.exe",
        "D:\progs\godot\Godot_v4.7.2-stable_win64_console.exe"
    )
    foreach ($candidate in $fallbackCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "Godot executable not found. Pass -GodotPath or set `$env:GODOT_PATH."
}

function Invoke-UidAndResourceAudit {
    param([string]$ProjRoot)

    $issues = [System.Collections.Generic.List[string]]::new()

    $gdFiles = Get-ChildItem -Path (Join-Path $ProjRoot "src"), (Join-Path $ProjRoot "tests") -Recurse -File -Filter "*.gd" -ErrorAction SilentlyContinue
    foreach ($gd in $gdFiles) {
        $uidFile = "$($gd.FullName).uid"
        if (-not (Test-Path -LiteralPath $uidFile)) {
            $issues.Add("Missing .uid sidecar: $($gd.FullName)")
        }
    }

    $resFiles = Get-ChildItem -Path (Join-Path $ProjRoot "scenes"), (Join-Path $ProjRoot "data"), (Join-Path $ProjRoot "tests") -Recurse -File -Include "*.tscn", "*.tres" -ErrorAction SilentlyContinue
    $resRegex = [regex]'res://([^"\s\]]+)'
    foreach ($rf in $resFiles) {
        $content = Get-Content -LiteralPath $rf.FullName -Raw
        foreach ($m in $resRegex.Matches($content)) {
            $rel = $m.Groups[1].Value -replace '/', '\'
            $target = Join-Path $ProjRoot $rel
            if (-not (Test-Path -LiteralPath $target)) {
                $issues.Add("Broken res:// reference in $($rf.Name): res://$($m.Groups[1].Value)")
            }
        }
    }

    return $issues
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath "project.godot"))) {
    Write-Error "project.godot not found at '$ProjectPath'."
    exit 2
}

$resolvedGodot = Resolve-GodotExecutable -ExplicitPath $GodotPath
Write-Host "Godot:   $resolvedGodot"
Write-Host "Project: $ProjectPath"
Write-Host "Scene:   $TestScene"

$uidIssues = @()
if ($CheckUids) {
    $uidIssues = @(Invoke-UidAndResourceAudit -ProjRoot $ProjectPath)
    if ($uidIssues.Count -eq 0) {
        Write-Host "[OK] UID & res:// reference audit passed."
    } else {
        Write-Host "[WARN] UID & res:// audit found $($uidIssues.Count) issue(s):"
        foreach ($item in $uidIssues) {
            Write-Host "  - $item"
        }
    }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()

try {
    $argList = @(
        "--headless",
        "--path", "`"$ProjectPath`"",
        $TestScene,
        "--",
        "--auto-quit"
    )
    $proc = Start-Process -FilePath $resolvedGodot `
        -ArgumentList $argList `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile

    $sw.Stop()
    $stdoutLines = @(Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue)
    $stderrLines = @(Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
    $allLines = @($stdoutLines + $stderrLines)

    if ($VerboseLog) {
        Write-Host "---------------- FULL GODOT OUTPUT ----------------"
        foreach ($line in $allLines) { Write-Host $line }
        Write-Host "---------------------------------------------------"
    } else {
        Write-Host "---------------- SUITE RESULTS ----------------"
        foreach ($line in $stdoutLines) {
            if ($line -match '^\[(PASS|FAIL)\]' -or $line -match '^\s*(SUMMARY:|RESULT:|FAIL:)') {
                if (-not $Filter -or $line -match $Filter -or $line -match '^\[FAIL\]' -or $line -match '^\s*(SUMMARY:|RESULT:|FAIL:)') {
                    Write-Host $line
                }
            }
        }
    }

    $scriptErrors = @($allLines | Where-Object {
        $_ -match 'SCRIPT ERROR:|Parse Error:|ERROR:|Cannot load|Orphan StringName|ObjectDB instances leaked'
    })
    $summaryLine = ($stdoutLines | Where-Object { $_ -match '^\s*SUMMARY:' } | Select-Object -Last 1)
    $greenLine = ($stdoutLines | Where-Object { $_ -match 'RESULT:\s*ALL TESTS PASSED \(GREEN\)' } | Select-Object -Last 1)
    $suiteLines = @($stdoutLines | Where-Object { $_ -match '^\[(PASS|FAIL)\]' })

    Write-Host "---------------- DIAGNOSTICS ----------------"
    Write-Host ("ExitCode: {0} | Suites: {1} | EngineErrors: {2} | Elapsed: {3:N2}s" -f $proc.ExitCode, $suiteLines.Count, $scriptErrors.Count, $sw.Elapsed.TotalSeconds)
    if ($summaryLine) {
        Write-Host $summaryLine.Trim()
    }

    if ($scriptErrors.Count -gt 0) {
        Write-Host "Engine / Script Errors detected:"
        foreach ($err in $scriptErrors) {
            Write-Host "  $err"
        }
    }

    $passed = ($proc.ExitCode -eq 0) -and [bool]$greenLine -and ($scriptErrors.Count -eq 0) -and ($uidIssues.Count -eq 0)
    if ($passed) {
        Write-Host "STATUS: GREEN"
        exit 0
    } else {
        Write-Host "STATUS: RED"
        exit 1
    }
} finally {
    Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
}
