Import-Module -Name "./Modules/MenuPrinter.psm1"
Import-Module -Name "./Modules/logging.psm1"
Import-Module -Name "./Modules/ShareData.psm1"
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | Select -index 0
$configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"


$operation = ""
do
{
  # Read-Host("DEBUG")
  $operation = &"./Scripts/Screens/PrintSiteMenu"

  if($operation -ne "Invalid")
  {
    if($operation -ne "Back to main menu")
    {
      Write-Log "$ScriptFileName" "Starting operation - $operation" "Program"
      switch($operation)
      {
        "Add New Site" { Read-SiteData $ScriptFileName }
        "Commit New Sites" {
          if(dir "$($configData.ShareFolderRootPath)")
          {
           &"./Scripts/ShareHelpers/AddNewSites"
          }
          else
          {
            Write-Host ""
            Write-Warning "No Department level folders found. Can't Add new sites. :("
            Write-Warning "Add at least one department level folder to process new sites."
            Write-Host ""
            PressEnterToContinue
          }
         }
        "Clear New Sites" { Remove-NonCommitedData $ScriptFileName -SiteData }
        "Remove Site" {
          $ExistingSites = Get-CSVData "./Data/Sites.csv"

          if($ExistingSites -ne $null)
          {
            Write-Host ""
            Write-Warning "Removing a site will delete A LOT of groups and permissions!"
            $confirmContinue = Read-Host("Type 'continue site removal' without quotes to proceed")
            if($confirmContinue -eq "continue site removal")
            {
              $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
              Import-Module -Name "./Modules/ShareManagement.psm1"
              [bool]$IsADDC = [int]$configData.IsADDC
              if($IsADDC)
              {
                Import-Module -Name "./Modules/LOCAL_AD.psm1"
              }
              else
              {
                Import-Module -Name "./Modules/REMOTE_AD.psm1"
              }

              Write-Host ""
              $prefix = Read-Host("Enter the site prefix for the site you want to remove")

              $dataFound = @()
              $dataFound += $ExistingSites | foreach { if($_.prefix -eq "$prefix") {return $true} else {return $false}}
              if($dataFound.Contains($true))
              {
                $SiteToRemove = $ExistingSites | Where {$_.prefix -eq $prefix}
                Write-Host "Site Name: $($SiteToRemove.name)  -  Site Prefix: $($SiteToRemove.prefix)"

                if(!($IsADDC)) { $creds = Get-Credential }
                $QueryArray = @()
                $QueryArray += "$($configData.GroupNamePrefix) $($SiteToRemove.prefix) *"

                $GroupsToRemove = Search-ADGroups $QueryArray $creds

                if($GroupsToRemove -eq "Error")
                {
                  Write-Host ""
                  Write-Warning "Server or Authentication Issue. Could not get AD groups to remove."
                }
                elseif($GroupsToRemove -eq "None")
                {
                  Remove-Item "./Data/Sites.csv"
                  foreach($site in $ExistingSites)
                  {
                    if($site.prefix -ne $prefix)
                    {
                      Save-CSVData $site.name $site.prefix "Sites"
                    }
                  }

                  Write-Host "No groups needed to be removed."
                }
                else
                {
                  Clear
                  Write-Host "These groups will be removed:"
                  $GroupsToRemove | foreach { Write-Host $_.Name }
                  Write-Host ""
                  Write-Host "Site Name: $($SiteToRemove.name)  -  Site Prefix: $($SiteToRemove.prefix)"
                  Write-Host ""
                  $removeSiteConfirm = Read-Host("Confirm Removal of above site data (site/groups/permissions) by typing 'delete site' without quotes")

                  if($removeSiteConfirm -eq "delete site")
                  {
                    $GroupNames = $GroupsToRemove | foreach { $_.Name }
                    Write-Host "Starting Permissions Removal..." -Foregroundcolor Yellow
                    Remove-SharePermissions $GroupNames
                    Write-Host "Starting Group Removal..." -Foregroundcolor Yellow
                    $Complete = Remove-ADGroups $GroupsToRemove $creds

                    if($Complete)
                    {
                      Remove-Item "./Data/Sites.csv"
                      foreach($site in $ExistingSites)
                      {
                        if($site.prefix -ne $prefix)
                        {
                          Save-CSVData $site.name $site.prefix "Sites"
                        }
                      }
                      Write-Host ""
                      Write-Host "You can now remove the '$($SiteToRemove.prefix)' OU from the '$($configData.ShareGroupsOU)' OU in AD" -Foregroundcolor Green
                    }
                    else
                    {
                      Write-Host ""
                      Write-Warning "Server or Authentication Error, Could not remove groups. Aborting Operation."
                    }
                  }
                }
              }
            }
          }
          else
          {
            Write-Host "No Sites to remove"
          }
          PressEnterToContinue
        }
      }
    }
  }
  else
  {
    PressEnterToContinue
  }
}
until($operation -eq "Back to main menu")
