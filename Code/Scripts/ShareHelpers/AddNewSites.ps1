Import-Module -Name "./Modules/MenuPrinter.psm1"
Import-Module -Name "./Modules/logging.psm1"
Import-Module -Name "./Modules/ShareData.psm1"
Import-Module -Name "./Modules/ReportGenerator.psm1"
Import-Module -Name "./Modules/ShareManagement.psm1"

$configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
[bool]$IsADDC = [int]$configData.IsADDC

if($IsADDC)
{
  Import-Module -Name "./Modules/LOCAL_AD.psm1"
}
else
{
  Import-Module -Name "./Modules/REMOTE_AD.psm1"
}

$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0
$UnmanagedFolderNames = Get-UnmanagedFolderNames $configData.ShareFolderRootPath
$NewSites = Get-CSVData "./Data/NewSites.csv"

if($NewSites -ne $Null -and $NewSites -ne "")
{
  Clear
  $offset = Get-PrintOffset $NewSites
  $totalErrors = 0
  Write-Host "You are about to process the new sites listed below:"
  Write-Host ""
  foreach($site in $NewSites)
  {
    PrintSiteData $site.name $site.prefix $offset -IsNew
  }

  Write-Host ""
  Write-Host "You will have one last chance to cancel this operation on the summary page after some info is collected"
  Write-Host ""
  $confirmStartCommit = Read-Host("Start Collecting Info? (Y/[N])")
  if($confirmStartCommit -eq "Y" -or $confirmStartCommit -eq "y")
  {
    Clear
    Write-Progress -Id 1 -Activity "Gathering Share Data" -Status "Collecting: Groups to add" -PercentComplete 0
    #GroupsToAdd Properties: [string]GroupName, [string]GroupOU, [string]Status
    $GroupsToAdd = Compare-ADGroups $configData.ShareFolderRootPath $NewSites $UnmanagedFolderNames

    if($GroupsToAdd -ne "Error")
    {
      Write-Progress -Id 1 -Activity "Gathering Share Data" -Status "Collecting: Folders to add" -PercentComplete 30
      #FoldersToAdd properties: [string]FolderName, [string]FolderPath, [string]Status
      $FoldersToAdd = Compare-SiteFolders $configData.ShareFolderRootPath $NewSites $UnmanagedFolderNames

      Write-Progress -Id 1 -Activity "Gathering Share Data" -Status "Collecting: Security permissions" -PercentComplete 60
      #SecurityToAdd properties: [string]FolderPath, [string]GroupName, [string]AccessLevel, [string]Status
      $SecurityToAdd = Compare-ShareSecurity $configData.ShareFolderRootPath $NewSites $UnmanagedFolderNames

      Write-Progress -Id 1 -Activity "Gathering Share Data" -Status "Done" -Completed #WARNING - See Warning note below

      Clear
      $totalAdds = ($GroupsToAdd | measure | select Count -ExpandProperty Count) +
                   ($FoldersToAdd | measure | select Count -ExpandProperty Count) +
                   ($SecurityToAdd | measure | select Count -ExpandProperty Count)

      if($totalAdds -eq 0)
      {
        #no action is required (sites already exist) Exit operation
        Write-Host "All new sites already exist and are setup. No actions required."
        Remove-Item "./Data/NewSites.csv"
        ForEach($site in $NewSites)
        {
          Save-CSVData $site.Name $site.Prefix "Sites"
        }
      }
      else
      {
        $done = $false
        do
        {
          $gCount = ($GroupsToAdd | measure | select Count -ExpandProperty Count)
          $fCount = ($FoldersToAdd | measure | select Count -ExpandProperty Count)
          $sCount = ($SecurityToAdd | measure | select Count -ExpandProperty Count)
          Clear
          Write-Host "Here is a quick summary of the operations about to be performed:"
          Write-Host "-----------------------------------------------------------------"
          Write-Host "Groups to create in AD      : $gCount"
          Write-Host "Site Folders to create      : $fCount"
          Write-Host "Security permissions to add : $sCount"
          Write-Host "-----------------------------------------------------------------"
          Write-Host "Total operations to perform : $totalAdds"
          Write-Host "_________________________________________________________________"
          Write-Host "Commands:"
          Write-Host "report       - Generate a detailed HTML report of all operations"
          Write-Host "start commit - perform all pending operations"
          Write-Host "cancel       - cancel this operation"
          Write-Host ""
          $command = Read-Host("Enter Command")

          switch($command.ToUpper())
          {
            "REPORT" {
              Write-Host ""
              Write-Host "Generating Report, please wait..."
              Get-AddReport "AddSite Report For" $NewSites $GroupsToAdd $FoldersToAdd $SecurityToAdd -preOp
            }
            "CANCEL" {
               Write-Host "Operation Aborted" -Foregroundcolor Red
               $done = $true
             }
            "START COMMIT" {
              [bool]$IsADDC = [int]$configData.IsADDC
              if(!($IsADDC)) { $global:RemoteAuthError = $false }

              if($fCount -ne $null -and $fCount -ne 0) { Add-SiteFolders $FoldersToAdd }
              if($gCount -ne $null -and $gCount -ne 0)
              {
                do
                {
                  Add-ADGroups $GroupsToAdd
                }
                until(!($global:RemoteAuthError))
              }
              #NOTE - Some remote sessions have issues adding security for groups just added to AD.
              #     - Not sure if it's a timing or network issue related to PSSessions, but I decided
              #     - to force a 20 second wait for remote sessions as an attempt to avoid issues.
              #     - Comment out the next line to disable the wait timer, but know that it may cause errors.
              if($gCount -ne $null -and $gCount -ne 0 -and -not $IsADDC) { PrintWaitTimer 20 "Allowing AD to update group info" }
              if($sCount -ne $null -and $sCount -ne 0) { Add-ShareSecurity $SecurityToAdd }

              if(!($IsADDC))
              {
                if(!($global:RemoteAuthError))
                {
                  Get-AddReport "AddSite Report For" $NewSites $GroupsToAdd $FoldersToAdd $SecurityToAdd
                  $done = $true
                }
                else
                {
                  Write-Warning "Authentication/Server Error. Please try again."
                  PressEnterToContinue
                }
              }
              else
              {
                Get-AddReport "AddSite Report For" $NewSites $GroupsToAdd $FoldersToAdd $SecurityToAdd
                $done = $true
              }

              Remove-Item "./Data/NewSites.csv"
              ForEach($site in $NewSites)
              {
                Save-CSVData $site.Name $site.Prefix "Sites"
              }
              Write-Host ""
              Write-Host "Done. If any errors occurred, you can try running option 3 on the main menu to re-check the share integrity." -Foregroundcolor Yellow
            }
          }
        }
        until($done)

        $date = Get-Date -format "MM-dd-yy"
        if((Test-Path("./Reports/temp_SiteAdd_$date.html")) -eq $true)
        {
          Remove-Item "./Reports/temp_SiteAdd_$date.html"
        }
      }
    }
    else
    {
      Write-Progress -Id 1 -Activity "Gathering Share Data" -Status "Done" -Completed #WARNING - See Warning note below
      Clear
      Write-Warning "Credentials do not have proper access or do not exist. Operation will not proceed."
    }
    #WARNING NOTE - Marking write-progress complete here causes artifacting. Mark complete before drawing any new screen information.
  }
  else
  {
    Write-Host "New Site Commit Aborted!" -Foregroundcolor Red
  }
}
else
{
  Write-Host ""
  Write-Host "No new sites to add"
}

PressEnterToContinue
