enum MyEnsure
{
    Absent
    Present
}

[DscResource()]
class MyScoop
{
    [DscProperty(Key)]
    [string] $MyScoopKey = 'MyScoopKey'

    [DscProperty()]
    [MyEnsure] $Ensure = [MyEnsure]::Present

    hidden [bool] IsInstalled()
    {
        return $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
    }

    [MyScoop] Get()
    {
        $current = [MyScoop]::new()
        $current.Ensure = if ($this.IsInstalled())
        {
            [MyEnsure]::Present 
        }
        else
        {
            [MyEnsure]::Absent 
        }
        return $current
    }

    [bool] Test()
    {
        
        $current = $this.Get()
        return ($current.Ensure -eq $this.Ensure)
    }

    [void] Set()
    {
        if ($this.Test())
        {
            return
        }

        if ($this.Ensure -eq [MyEnsure]::Present)
        {
            # Install Scoop as admin
            Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"
        }
        elseif ($this.Ensure -eq [MyEnsure]::Absent)
        {
            scoop uninstall scoop --purge
            # Remove-Item -Recurse -Force ~\scoop
        }
    }
}
