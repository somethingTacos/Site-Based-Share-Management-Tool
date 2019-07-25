$configData = Import-LocalizedData -BaseDirectory "../Data/" -FileName "config.psd1" -EA SilentlyContinue

if($configData -ne $null)
{
  Write-Host "Delete all orphaned groups recursivly from '$($configData.ShareFolderRootPath)'?"
  Write-Warning "This process can take a long time!"
  $confirm = Read-Host("Type 'remove' without quotes to start removal")

  if($confirm -eq "remove")
  {
    Write-Host "Starting orphaned groups removal..."
    Write-Host ""
    $access = Get-NTFSAccess $configData.ShareFolderRootPath
    $access | % {
      if($_.Account -like "S-1-5*")
      {
        Remove-NTFSAccess -Path "$($configData.ShareFolderRootPath)" -Account $_.Account -AccessRights $_.AccessRights
        Write-Host "$($configData.ShareFolderRootPath)  ::  Account Removed: $($_.Account)"
      }
    }

    dir $configData.ShareFolderRootPath -Recurse | % {
      $path = $_.FullName
      $access = Get-NTFSAccess $path
      $access | % {
        if($_.Account -like "S-1-5*")
        {
          Remove-NTFSAccess -Path "$path" -Account $_.Account -AccessRights $_.AccessRights
          Write-Host "$path  ::  Account Removed: $($_.Account)"
        }
      }
    }

    Write-Host ""
    Write-Host "Done. I highly recommend running 'Check Share Integrity' to ensure the share security is intact."
  }
}
else
{
  Write-Host "No config data found. Exiting..."
}

Read-Host("Press Enter to exit")
