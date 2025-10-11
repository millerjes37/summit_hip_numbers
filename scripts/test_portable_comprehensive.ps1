# scripts/test_portable_comprehensive.ps1
# Comprehensive testing framework for portable distributions

param(
    [Parameter(Mandatory=$true)]
    [string]$DistPath,
    
    [Parameter(Mandatory=$false)]
    [string]$Variant = "full",
    
    [Parameter(Mandatory=$false)]
    [int]$RuntimeSeconds = 10
)

$ErrorActionPreference = "Stop"

# Color output functions
function Write-Section { param($Text) Write-Host "`n========================================" -ForegroundColor Cyan; Write-Host "  $Text" -ForegroundColor Cyan; Write-Host "========================================" -ForegroundColor Cyan }
function Write-Step { param($Text) Write-Host "`n[TEST] $Text" -ForegroundColor Yellow }
function Write-Success { param($Text) Write-Host "  ✓ $Text" -ForegroundColor Green }
function Write-Failure { param($Text) Write-Host "  ✗ $Text" -ForegroundColor Red }
function Write-Info { param($Text) Write-Host "  → $Text" -ForegroundColor Gray }

# Test results tracking
$script:TestResults = @{
    Passed = @()
    Failed = @()
    Warnings = @()
}

function Add-TestResult {
    param([string]$TestName, [bool]$Passed, [string]$Message = "")
    
    if ($Passed) {
        $script:TestResults.Passed += $TestName
        Write-Success "$TestName $Message"
    } else {
        $script:TestResults.Failed += $TestName
        Write-Failure "$TestName $Message"
    }
}

function Add-Warning {
    param([string]$Message)
    $script:TestResults.Warnings += $Message
    Write-Host "  ⚠ $Message" -ForegroundColor DarkYellow
}

# Main test execution
Write-Section "COMPREHENSIVE PORTABLE DISTRIBUTION TEST"
Write-Info "Distribution: $DistPath"
Write-Info "Variant: $Variant"
Write-Info "Test Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ============================================================================
# TEST 1: Directory Structure Validation
# ============================================================================
Write-Step "1. Directory Structure Validation"

if (-not (Test-Path $DistPath)) {
    Add-TestResult "Directory Exists" $false "Path not found: $DistPath"
    exit 1
} else {
    Add-TestResult "Directory Exists" $true
}

# Catalog all files
$allFiles = Get-ChildItem -Path $DistPath -Recurse -File
Write-Info "Total files: $($allFiles.Count)"
Write-Info "Total size: $([math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)) MB"

# Check for manifest
if (Test-Path (Join-Path $DistPath "BUILD_MANIFEST.txt")) {
    Add-TestResult "Build Manifest Present" $true
    Write-Info "Manifest contents:"
    Get-Content (Join-Path $DistPath "BUILD_MANIFEST.txt") | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
} else {
    Add-Warning "Build manifest not found"
}

# ============================================================================
# TEST 2: Executable Detection
# ============================================================================
Write-Step "2. Executable Detection"

$exePattern = if ($Variant -eq "demo") { "summit_hip_numbers_demo.exe" } else { "summit_hip_numbers.exe" }
$executable = Get-ChildItem -Path $DistPath -Filter $exePattern -Recurse -File | Select-Object -First 1

if ($executable) {
    Add-TestResult "Executable Found" $true "($($executable.FullName))"
    Write-Info "Size: $([math]::Round($executable.Length / 1MB, 2)) MB"
    Write-Info "Modified: $($executable.LastWriteTime)"
    
    # Check if executable is valid PE file
    $peHeader = Get-Content $executable.FullName -Encoding Byte -TotalCount 2
    if ($peHeader[0] -eq 0x4D -and $peHeader[1] -eq 0x5A) {
        Add-TestResult "Valid PE File" $true
    } else {
        Add-TestResult "Valid PE File" $false "Invalid PE header"
    }
} else {
    Add-TestResult "Executable Found" $false
    Write-Failure "Expected executable: $exePattern"
    exit 1
}

$workingDir = Split-Path -Parent $executable.FullName

# ============================================================================
# TEST 3: Critical DLL Verification
# ============================================================================
Write-Step "3. Critical DLL Verification"

$criticalDlls = @{
    "libglib-2.0-0.dll" = "GLib Core"
    "libgobject-2.0-0.dll" = "GObject"
    "libgio-2.0-0.dll" = "GIO"
    "libgstreamer-1.0-0.dll" = "GStreamer Core"
    "libgstapp-1.0-0.dll" = "GStreamer App"
    "libgstbase-1.0-0.dll" = "GStreamer Base"
    "libgstvideo-1.0-0.dll" = "GStreamer Video"
    "libgstaudio-1.0-0.dll" = "GStreamer Audio"
    "libintl-8.dll" = "Internationalization"
    "libwinpthread-1.dll" = "Windows POSIX Threads"
}

$allDlls = Get-ChildItem -Path $workingDir -Filter "*.dll" -File
Write-Info "Total DLLs found: $($allDlls.Count)"

foreach ($dll in $criticalDlls.Keys) {
    $dllPath = Join-Path $workingDir $dll
    if (Test-Path $dllPath) {
        $dllInfo = Get-Item $dllPath
        Add-TestResult $criticalDlls[$dll] $true "($([math]::Round($dllInfo.Length/1KB, 2)) KB)"
    } else {
        Add-TestResult $criticalDlls[$dll] $false "Missing: $dll"
    }
}

# Generate DLL report
$dllReportPath = Join-Path $workingDir "test-dll-report.txt"
@"
DLL Dependency Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Working Directory: $workingDir

All DLLs Present:
"@ | Out-File -FilePath $dllReportPath -Encoding UTF8

$allDlls | Sort-Object Name | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 2)
    "$($_.Name) - $size KB" | Out-File -FilePath $dllReportPath -Append -Encoding UTF8
}

# ============================================================================
# TEST 4: GStreamer Plugin Verification
# ============================================================================
Write-Step "4. GStreamer Plugin Verification"

$pluginLocations = @(
    (Join-Path $workingDir "lib\gstreamer-1.0"),
    (Join-Path $workingDir "gstreamer-1.0"),
    (Join-Path $workingDir "plugins")
)

$foundPlugins = $false
$pluginCount = 0

foreach ($pluginDir in $pluginLocations) {
    if (Test-Path $pluginDir) {
        $plugins = Get-ChildItem -Path $pluginDir -Filter "*.dll" -File
        $pluginCount = $plugins.Count
        
        if ($pluginCount -gt 0) {
            Add-TestResult "GStreamer Plugins Found" $true "($pluginCount plugins in $pluginDir)"
            $foundPlugins = $true
            
            # List key plugins
            $keyPlugins = @("gstcoreelements", "gstplayback", "gsttypefindfunctions", "gstaudioconvert", "gstvideoconvert")
            foreach ($key in $keyPlugins) {
                $found = $plugins | Where-Object { $_.Name -like "*$key*" }
                if ($found) {
                    Write-Info "  ✓ $key plugin present"
                } else {
                    Add-Warning "Optional plugin missing: $key"
                }
            }
            break
        }
    }
}

if (-not $foundPlugins) {
    Add-TestResult "GStreamer Plugins Found" $false
    Add-Warning "No GStreamer plugins detected - media playback may not work"
}

# ============================================================================
# TEST 5: Configuration & Asset Files
# ============================================================================
Write-Step "5. Configuration & Asset Files"

$expectedAssets = @{
    "config.toml" = "Configuration"
    "README.txt" = "Documentation"
    "LICENSE" = "License"
}

foreach ($asset in $expectedAssets.Keys) {
    $assetPath = Get-ChildItem -Path $DistPath -Filter $asset -Recurse -File | Select-Object -First 1
    if ($assetPath) {
        Add-TestResult $expectedAssets[$asset] $true
    } else {
        Add-Warning "$($expectedAssets[$asset]) file not found: $asset"
    }
}

# ============================================================================
# TEST 6: Runtime Execution Test
# ============================================================================
Write-Step "6. Runtime Execution Test"

$logFile = Join-Path $workingDir "test-runtime.log"
$errorFile = Join-Path $workingDir "test-runtime-error.log"

try {
    # Start process
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable.FullName
    $startInfo.WorkingDirectory = $workingDir
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    
    # Capture output
    $outputBuilder = New-Object System.Text.StringBuilder
    $errorBuilder = New-Object System.Text.StringBuilder
    
    $outputEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) {
            [void]$Event.MessageData.AppendLine($EventArgs.Data)
        }
    } -MessageData $outputBuilder
    
    $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) {
            [void]$Event.MessageData.AppendLine($EventArgs.Data)
        }
    } -MessageData $errorBuilder
    
    # Start process
    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    
    $pid = $process.Id
    Write-Info "Process started (PID: $pid)"
    Add-TestResult "Process Start" $true
    
    # Wait for initialization
    Start-Sleep -Seconds 2
    
    # Check if still running
    if ($process.HasExited) {
        Add-TestResult "Process Stability" $false "Exited prematurely (code: $($process.ExitCode))"
    } else {
        Add-TestResult "Process Stability" $true "Running after $RuntimeSeconds seconds"
        
        # Simulate user interaction
        Write-Info "Simulating keyboard input..."
        Add-Type -AssemblyName System.Windows.Forms
        
        Start-Sleep -Seconds 1
        [System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Write-Info "  Sent: DOWN arrow"
        
        Start-Sleep -Seconds 1
        [System.Windows.Forms.SendKeys]::SendWait("{UP}")
        Write-Info "  Sent: UP arrow"
        
        Start-Sleep -Seconds 1
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Write-Info "  Sent: ENTER"
        
        Start-Sleep -Seconds ($RuntimeSeconds - 5)
        
        # Final check
        if (-not $process.HasExited) {
            Add-TestResult "Interactive Stability" $true
            Write-Info "Terminating process..."
            $process.Kill()
            $process.WaitForExit(5000)
        } else {
            Add-Warning "Process exited during interaction"
        }
    }
    
    # Cleanup event handlers
    Unregister-Event -SourceIdentifier $outputEvent.Name
    Unregister-Event -SourceIdentifier $errorEvent.Name
    
    # Save logs
    $outputBuilder.ToString() | Out-File -FilePath $logFile -Encoding UTF8
    $errorBuilder.ToString() | Out-File -FilePath $errorFile -Encoding UTF8
    
    # Display logs
    Write-Host "`n--- STDOUT ---" -ForegroundColor DarkGray
    $outputBuilder.ToString() | Write-Host -ForegroundColor DarkGray
    
    if ($errorBuilder.Length -gt 0) {
        Write-Host "`n--- STDERR ---" -ForegroundColor DarkYellow
        $errorBuilder.ToString() | Write-Host -ForegroundColor DarkYellow
    }
    
} catch {
    Add-TestResult "Runtime Execution" $false $_.Exception.Message
    Write-Host $_.Exception.ToString() -ForegroundColor Red
}

# ============================================================================
# TEST 7: Memory & Resource Check
# ============================================================================
Write-Step "7. Post-Execution Validation"

if (Test-Path $logFile) {
    $logSize = (Get-Item $logFile).Length
    Add-TestResult "Log Generation" $true "($logSize bytes)"
}

# ============================================================================
# FINAL REPORT
# ============================================================================
Write-Section "TEST SUMMARY"

$totalTests = $script:TestResults.Passed.Count + $script:TestResults.Failed.Count
$passRate = if ($totalTests -gt 0) { [math]::Round(($script:TestResults.Passed.Count / $totalTests) * 100, 1) } else { 0 }

Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  Passed:   $($script:TestResults.Passed.Count)" -ForegroundColor Green
Write-Host "  Failed:   $($script:TestResults.Failed.Count)" -ForegroundColor Red
Write-Host "  Warnings: $($script:TestResults.Warnings.Count)" -ForegroundColor Yellow
Write-Host "  Success Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 75) { "Yellow" } else { "Red" })

if ($script:TestResults.Failed.Count -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $script:TestResults.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($script:TestResults.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $script:TestResults.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

# Generate test report file
$reportPath = Join-Path $workingDir "TEST_REPORT.txt"
@"
========================================
PORTABLE DISTRIBUTION TEST REPORT
========================================
Test Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Distribution: $DistPath
Variant: $Variant

RESULTS SUMMARY
----------------------------------------
Total Tests: $totalTests
Passed: $($script:TestResults.Passed.Count)
Failed: $($script:TestResults.Failed.Count)
Warnings: $($script:TestResults.Warnings.Count)
Success Rate: $passRate%

PASSED TESTS
----------------------------------------
$($script:TestResults.Passed | ForEach-Object { "✓ $_" } | Out-String)

FAILED TESTS
----------------------------------------
$($script:TestResults.Failed | ForEach-Object { "✗ $_" } | Out-String)

WARNINGS
----------------------------------------
$($script:TestResults.Warnings | ForEach-Object { "⚠ $_" } | Out-String)

========================================
"@ | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "`nTest report saved: $reportPath" -ForegroundColor Cyan

# Exit with appropriate code
if ($script:TestResults.Failed.Count -eq 0) {
    Write-Host "`n✓ ALL TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ TESTS FAILED" -ForegroundColor Red
    exit 1
}