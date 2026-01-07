# Simple test to see if Set is being called

$testJson = @{
    packageName = '7zip'
    ensure      = 'Present'
    version     = 'latest'
} | ConvertTo-Json

Write-Host "=== Calling Test operation ===" -ForegroundColor Cyan
$testOutput = $testJson | & pwsh -NoProfile -File .\ChocolateyPackage.ps1 Test 2>&1
Write-Host "STDOUT:" -ForegroundColor Yellow
$testOutput | Where-Object { $_ -is [string] -and $_ -notmatch '^\[DEBUG\]' } | Write-Host
Write-Host ""
Write-Host "STDERR (Debug logs):" -ForegroundColor Yellow
$testOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -or ($_ -is [string] -and $_ -match '^\[DEBUG\]') } | Write-Host
Write-Host ""

Write-Host "=== Parsing Test result ===" -ForegroundColor Cyan
$testJson = $testOutput | Where-Object { $_ -is [string] -and $_ -notmatch '^\[DEBUG\]' } | Out-String
try {
    $testResult = $testJson | ConvertFrom-Json
    Write-Host "Test result parsed successfully:" -ForegroundColor Green
    Write-Host "  _inDesiredState: $($testResult._inDesiredState)" -ForegroundColor $(if ($testResult._inDesiredState) { 'Red' } else { 'Green' })
    Write-Host "  ensure: $($testResult.ensure)"
    Write-Host "  state: $($testResult.state)"
}
catch {
    Write-Host "Failed to parse Test output as JSON" -ForegroundColor Red
    Write-Host "Raw output was:" -ForegroundColor Yellow
    Write-Host $testJson
}

Write-Host ""
Write-Host "=== Calling Set operation ===" -ForegroundColor Cyan
$setOutput = $testJson | & pwsh -NoProfile -File .\ChocolateyPackage.ps1 Set 2>&1
Write-Host "STDOUT:" -ForegroundColor Yellow
$setOutput | Where-Object { $_ -is [string] -and $_ -notmatch '^\[DEBUG\]' } | Write-Host
Write-Host ""
Write-Host "STDERR (Debug logs):" -ForegroundColor Yellow  
$setOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -or ($_ -is [string] -and $_ -match '^\[DEBUG\]') } | Write-Host