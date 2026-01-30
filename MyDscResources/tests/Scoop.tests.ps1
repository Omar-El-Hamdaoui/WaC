# Scoop.tests.ps1
# Tests Pester pour valider la ressource DSC Scoop

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\resources\Scoop\Scoop.ps1"
    . $scriptPath
}

#############Partie Get##############

Describe 'Partie Get' {
    Context 'Get-ScoopPath'{
    
        AfterEach {
            Remove-Item env:SCOOP -ErrorAction SilentlyContinue
        }
        
        It 'Retourne $env:SCOOP si défini' {
            $env:SCOOP = 'C:\CustomScoop'
            Get-ScoopPath | Should -Be 'C:\CustomScoop'
        }
        
        It 'Retourne le chemin par défaut si le dossier existe' {
            $defaultPath = Join-Path $env:USERPROFILE 'scoop'
            Mock Test-Path { $true } -ParameterFilter { $Path -eq $defaultPath }
            
            Get-ScoopPath | Should -Be $defaultPath
        }
        
        It 'Retourne $null si Scoop non trouvé' {
            Mock Test-Path { $false }
            Get-ScoopPath | Should -BeNullOrEmpty
        }
    }


    Context 'Test-ScoopInstalled' {
        
        It 'Retourne $true si Get-ScoopPath retourne un chemin' {
            Mock Get-ScoopPath { 'C:\scoop' }
            Test-ScoopInstalled | Should -Be $true
        }
        
        It 'Retourne $false si Get-ScoopPath retourne $null' {
            Mock Get-ScoopPath { $null }
            Test-ScoopInstalled | Should -Be $false
        }
    }

    Context 'Get-ScoopVersion' {
            
        It 'Retourne $null si non installé' {
            Mock Test-ScoopInstalled { $false }
            Get-ScoopVersion | Should -BeNullOrEmpty
        }
        
        It 'Retourne $null en cas d''erreur' {
            Mock Test-ScoopInstalled { $true }
            Mock Invoke-Expression { throw "Error" }
            
            Get-ScoopVersion | Should -BeNullOrEmpty
        }
    }

    Context 'Get-ResourceState' {
    
        It 'Retourne Absent si non installé' {
            Mock Test-ScoopInstalled { $false }
            
            $result = Get-ResourceState -InputObject @{ name = 'Scoop' }
            
            $result.ensure | Should -Be 'Absent'
            $result.name | Should -Be 'Scoop'
        }
        
        It 'Retourne Present avec version et path si installé' {
            Mock Test-ScoopInstalled { $true }
            Mock Get-ScoopVersion { '1.0.0' }
            Mock Get-ScoopPath { 'C:\scoop' }
            
            $result = Get-ResourceState -InputObject @{ name = 'Scoop' }
            
            $result.ensure | Should -Be 'Present'
            $result.version | Should -Be '1.0.0'
            $result.installPath | Should -Be 'C:\scoop'
        }
        
        It 'Utilise "Scoop" par défaut si name non fourni' {
            Mock Test-ScoopInstalled { $false }
            
            $result = Get-ResourceState 
            
            $result.name | Should -Be 'Scoop'
        }
        
    }
}

#############Partie Test##############

Describe 'Partie Test' {
    Context 'Test-ResourceState'{

        It 'Retourne $true si l''état actuel correspond à l''état désiré' {
            $currentState = @{
                ensure = 'Present'
            }
            $desiredState = @{
                ensure = 'Present'
            }
            
            Test-ResourceState -CurrentState $currentState -DesiredState $desiredState | Should -Be $true
        }

        It 'Retourne _inDesiredState = true si état actuel = état désiré (Present)' {
            Mock Get-ResourceState { @{ name = 'Scoop'; ensure = 'Present' } }

            $result = Test-ResourceState -InputObject @{ ensure = 'Present' }
            
            $result._inDesiredState | Should -Be $true
        }
        
        It 'Retourne _inDesiredState = false si état actuel n''est pas l''état désiré' {
            Mock Get-ResourceState { @{ name = 'Scoop'; ensure = 'Absent' } }

            $result = Test-ResourceState -InputObject @{ ensure = 'Present' }

            $result._inDesiredState | Should -Be $false
        }
        
        It 'Utilise Present par défaut si ensure non spécifié' {
            Mock Get-ResourceState { @{ name = 'Scoop'; ensure = 'Present' } }

            $result = Test-ResourceState 

            $result._inDesiredState | Should -Be $true
        }
        
        It 'Gère les erreurs et retourne un état valide' {
            Mock Get-ResourceState { throw "Erreur" }

            $result = Test-ResourceState 

            $result.ensure | Should -Be 'Absent'
            $result._inDesiredState | Should -Be $false
            $result.error | Should -Not -BeNullOrEmpty
        }
    }
}


#############Partie Set##############





AfterAll {
    Write-Host "`nScoop tests completed" -ForegroundColor Green
}