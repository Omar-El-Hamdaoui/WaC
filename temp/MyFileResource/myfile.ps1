param(
 [Parameter(Position = 0)]
 [ValidateSet('Get', 'Set', 'Test', 'Export')]
 [string]$Operation = 'Get'
)
# Read input from stdin
$inputJson = [Console]::In.ReadToEnd()
$inputObject = $inputJson | ConvertFrom-Json
function Get-ResourceState {
 param($InputObject)
 
 $state = @{
 path = $InputObject.path
 ensure = 'Absent'
 content = $null
 }
 
 if (Test-Path -Path $InputObject.path) {
 $state.ensure = 'Present'
 if ((Get-Item $InputObject.path).PSIsContainer -eq $false) {
 $state.content = Get-Content -Path $InputObject.path -Raw
 }
 }
 
 return $state
}
function Test-ResourceState {
 param($InputObject)
 
 $currentState = Get-ResourceState -InputObject $InputObject
 $desiredState = $InputObject
 
 $inDesiredState = $true
 
 if ($desiredState.ensure -eq 'Present') {
 if ($currentState.ensure -ne 'Present') {
 $inDesiredState = $false
 }
 elseif ($null -ne $desiredState.content -and
 $currentState.content -ne $desiredState.content) {
 $inDesiredState = $false
 }
 }
 else {
 $inDesiredState = $currentState.ensure -eq 'Absent'
 }
 
 $currentState._inDesiredState = $inDesiredState
 return $currentState
}
function Set-ResourceState {
 param($InputObject)
 
 if ($InputObject.ensure -eq 'Present') {
 $dir = Split-Path -Path $InputObject.path -Parent
 if ($dir -and -not (Test-Path -Path $dir)) {
 New-Item -Path $dir -ItemType Directory -Force | Out-Null
 }
 
 if ($null -ne $InputObject.content) {
 Set-Content -Path $InputObject.path -Value $InputObject.content -Force
 }
 else {
 New-Item -Path $InputObject.path -ItemType File -Force | Out-Null
 }
 }
 else {
 if (Test-Path -Path $InputObject.path) {
 Remove-Item -Path $InputObject.path -Force
 }
 }
 
 return Get-ResourceState -InputObject $InputObject
}

# Add Export function
function Export-ResourceInstances {
 $results = @()
 
 # Example: Export all .txt files from a known location
 $searchPath = "C:\ProgramData\DSCConfigs"
 
 if (Test-Path -Path $searchPath) {
 Get-ChildItem -Path $searchPath -Filter "*.txt" -File | ForEach-Object {
 $instance = @{
 path = $_.FullName
 content = Get-Content -Path $_.FullName -Raw
 ensure = 'Present'
 }
 $results += $instance
 }
 }
 
 return @{ resources = $results }
}



$result = switch ($Operation) {
 'Get' { Get-ResourceState -InputObject $inputObject }
 'Test' { Test-ResourceState -InputObject $inputObject }
 'Set' { Set-ResourceState -InputObject $inputObject }
 'Export' { Export-ResourceInstances }
}
# Output as JSON
$result | ConvertTo-Json -Compress
