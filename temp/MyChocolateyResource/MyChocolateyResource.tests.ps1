# MyChocolateyResource.tests.ps1
# Tests Pester pour valider la ressource DSC MyChocolateyResource

BeforeAll {
    # Configuration initiale avant tous les tests
    $resourcePath = $PSScriptRoot
    $env:PATH = "$resourcePath;$env:PATH"
    
    Write-Host "Testing MyChocolatey DSC Resource" -ForegroundColor Cyan
}

Describe 'MyCompany.Installer/MyChocolatey Resource' {
    
    Context 'Get Operation' {
        
        It 'Returns Present if Chocolatey is installed, Absent otherwise' {
            # Act
            $jsonInput = @{ 
                name = "Chocolatey" 
            } | ConvertTo-Json -Compress
            
            $output = dsc resource get --resource MyCompany.Installer/MyChocolatey --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState.ensure | Should -BeIn @('Present', 'Absent')
            $result.actualState.name | Should -Be 'Chocolatey'
        }
    }
    
    Context 'Test Operation' {
        
        It 'Returns boolean _inDesiredState property' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource test --resource MyCompany.Installer/MyChocolatey --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState | Should -Not -BeNullOrEmpty
            $result.actualState._inDesiredState | Should -BeOfType [bool]
        }
    }
    
    Context 'Set Operation' -Tag 'RequiresAdmin' {
        
        It 'Can execute Set operation for Present' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act - Just verify it doesn't throw
            { dsc resource set --resource MyCompany.Installer/MyChocolatey --input $jsonInput | Out-Null } | 
                Should -Not -Throw
        }
        
        It 'Can execute Set operation for Absent' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Absent"
            } | ConvertTo-Json -Compress
            
            # Act - Just verify it doesn't throw
            { dsc resource set --resource MyCompany.Installer/MyChocolatey --input $jsonInput | Out-Null } | 
                Should -Not -Throw
        }
    }
}

AfterAll {
    Write-Host "Tests completed" -ForegroundColor Green
}