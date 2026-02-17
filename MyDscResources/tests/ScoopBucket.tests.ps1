# Scoop.tests.ps1
# Tests Pester pour valider la ressource DSC Scoop

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\resources\ScoopBucket\MyScoopBucket.ps1"
    . $scriptPath
}


Describe 'Partie Get' { 
    Context 'Get-ResourceState'{ 
        It 'Retourne le nom et ensure Present si le bucket est installé' { 
            Mock Test-ScoopBucketInstalled { $true } 
            $inputObject = @{ name = 'versions' } 
            $result = Get-ResourceState -InputObject $inputObject 
            $result.name | Should -Be 'versions' 
            $result.ensure | Should -Be 'Present' } 
            
        It 'Retourne le nom et ensure Absent si le bucket n''est pas installé' { 
            Mock Test-ScoopBucketInstalled { $false } 
            $inputObject = @{ name = 'versions' } 
            $result = Get-ResourceState -InputObject $inputObject 
            $result.name | Should -Be 'versions' 
            $result.ensure | Should -Be 'Absent' 
        } 
    }
}

Describe 'Partie Test' {
    Context 'Test-ResourceState' { 
        It 'Retourne _inDesiredState true si le bucket est dans l état désiré' {
            Mock Test-ScoopBucketInstalled { $true } 
            $inputObject = @{ name = 'versions'; ensure = 'Present' } 
            $result = Test-ResourceState -InputObject $inputObject 
            $result._inDesiredState | Should -Be $true 
        } 
        It 'Retourne _inDesiredState false si le bucket n est pas dans l état désiré' {
            Mock Test-ScoopBucketInstalled { $false } 
            $inputObject = @{ name = 'versions'; ensure = 'Present' } 
            $result = Test-ResourceState -InputObject $inputObject 
            $result._inDesiredState | Should -Be $false 
        } 
    } 
}

AfterAll {
    Write-Host "`nScoop tests completed" -ForegroundColor Green
}
