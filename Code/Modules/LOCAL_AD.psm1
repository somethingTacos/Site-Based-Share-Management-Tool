Function Compare-ADGroups($path, $sites, $UnmanagedFolderNames)
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $GroupsToAdd = @()

  ImportSystemModules
  Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Starting..." -PercentComplete 0

  $ExistingFolderInfo = Get-CSVData "./Data/Folders.csv"
  $GeneralFolderCount = $ExistingFolderInfo | Where { $_.hasgeneral -eq "1" } | measure | select Count -ExpandProperty Count

  $folderCount = dir $path | measure | select Count -ExpandProperty Count
  $workingFolderCount = $folderCount - $UnmanagedFolderNames.Count
  $siteCount = $sites | measure | select Count -ExpandProperty Count
  $ProgressMax = $workingFolderCount * $siteCount * 2 + $GeneralFolderCount # x2 to account for modify and readonly groups
  $CompletedCount = 0
  $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
  $sites | ForEach-Object {
    $groupPrefix = $configData.GroupNamePrefix
    $ShareGroupsOU = $configData.ShareGroupsOU
    $DCPath = $configData.DCPath
    $currentSite = $_.prefix

    dir $path | ForEach-Object {

      if(!($UnmanagedFolderNames.Contains($_.Name)))
      {
        if($groupPrefix -ne $null -and $groupPrefix -ne "")
        {
          $ModifyGroupToCheck = "$groupPrefix $currentSite $_ MODIFY"
          $ReadOnlyGroupToCheck = "$groupPrefix $currentSite $_ READONLY"
        }
        else
        {
          $ModifyGroupToCheck = "$currentSite $_ MODIFY"
          $ReadOnlyGroupToCheck = "$currentSite $_ READONLY"
        }

        $ModifyGroupToCheck = $ModifyGroupToCheck.ToUpper()
        $ReadOnlyGroupToCheck = $ReadOnlyGroupToCheck.ToUpper()

        if($CompletedCount -lt $ProgressMax + 1)
        {
          $CompletedCount += 1
          $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
          Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $ModifyGroupToCheck"
        }

        $groupExists = $false
        try { if(Get-ADGroup $ModifyGroupToCheck) { $groupExists = $true }} catch { } #do nothing

        if(!($groupExists))
        {
          $GroupOU = "OU=MODIFY,OU=$currentSite,OU=$ShareGroupsOU,$DCPath"
          $newGroupInfo = New-Object PsObject
          $newGroupInfo | Add-Member -Type NoteProperty -Name 'GroupName' -Value $ModifyGroupToCheck
          $newGroupInfo | Add-Member -Type NoteProperty -Name 'GroupOU' -Value $GroupOU
          $newGroupInfo | Add-Member -Type NoteProperty -Name 'Status' -Value "Pending"
          $GroupsToAdd += $newGroupInfo
        }
        if($CompletedCount -lt $ProgressMax + 1)
        {
          $CompletedCount += 1
          $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
          Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $ReadOnlyGroupToCheck"
        }

        $groupExists = $false
        try { if(Get-ADGroup $ReadOnlyGroupToCheck) { $groupExists = $true }} catch { } #do nothing

        if(!($groupExists))
        {
          $GroupOU = "OU=READONLY,OU=$currentSite,OU=$ShareGroupsOU,$DCPath"
          $newGroupInfo = New-Object psobject
          $newGroupInfo | Add-Member -Type NoteProperty -Name 'GroupName' -Value $ReadOnlyGroupToCheck
          $newGroupInfo | Add-Member -Type NoteProperty -Name 'GroupOU' -Value $GroupOU
          $newGroupInfo | Add-Member -Type NoteProperty -Name 'Status' -Value "Pending"
          $GroupsToAdd += $newGroupInfo
        }
      }
    }
  }

  Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Done" -Completed

  return $GroupsToAdd
}

function Add-ADGroups($GroupsToAdd)
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0

  ImportSystemModules

  #GroupsToAdd Properties: [string]GroupName, [string]GroupOU, [string]Status
  ForEach($GroupInfo in $GroupsToAdd)
  {
    $OUExists = $false

    $GroupSplatter = @{
      Name = "$($GroupInfo.GroupName)"
      GroupCategory = 'Security'
      GroupScope = 'Global'
      SamAccountName = "$($GroupInfo.GroupName)"
      Description = "A Company Share Security Group"
      Path = "$($GroupInfo.GroupOU)"
    }

    try { if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""$($GroupInfo.GroupOU)""") {$OUExists = $true} } catch { } #do nothing
    if(!($OUExists))
    {
      #OUPath was not found. Check Site OU
      $dnArray = $GroupInfo.GroupOU.Split(',')
      $SiteDNArray = $dnArray[1..$($dnArray.Count)]
      $SiteOU = [System.String]::Join(',',$SiteDNArray)
      $OUExists = $false
      try { if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""$($SiteOU)""") {$OUExists = $true} } catch { } #do nothing
      if(!($OUExists))
      {
        if($configData.GroupNamePrefix -ne "")
        {
          $SitePrefix = $GroupInfo.GroupName.Split(' ') | select -Index 1
        }
        else
        {
          $SitePrefix = $GroupInfo.GroupName.Split(' ') | select -Index 0
        }
        $SiteOUCreated = $false
        New-ADOrganizationalUnit -Name "$SitePrefix" -Path "OU=$($configData.ShareGroupsOU),$($configData.DCPath)"
        try { if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""$($SiteOU)""") {$SiteOUCreated = $true} } catch { } #do nothing
        if(!($SiteOUCreated))
        {
          Write-Warning "Automatic Creation of OU: '$SitePrefix'"
          Write-Warning "At: 'OU=$($configData.ShareGroupsOU),$($configData.DCPath)'"
          Write-Warning "Failed! Continuing Operation may cause additional errors!"
          Write-Host ""
          $cancelOp = Read-Host("Cancel Remaining Operations? (Y/[N])")

          if($cancelOp -eq "Y" -or $cancelOp -eq "y")
          {
            break;
          }
        }
      }

      $AccessOUName = $GroupInfo.GroupName.Split(' ') | select -Last 1
      $AccessOUCreated = $false
      New-ADOrganizationalUnit -Name "$AccessOUName" -Path "$SiteOU"
      try { if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""$($GroupInfo.GroupOU)""") {$AccessOUCreated = $true} } catch { } #do nothing
      if(!($AccessOUCreated))
      {
        Write-Warning "Automatic Creation of OU: '$AccessOUName'"
        Write-Warning "At: '$SiteOU'"
        Write-Warning "Failed! Continuing Operation may cause additional errors!"
        Write-Host ""
        $cancelOp = Read-Host("Cancel Remaining Operations? (Y/[N])")

        if($cancelOp -eq "Y" -or $cancelOp -eq "y")
        {
          break;
        }
      }

      New-ADGroup @GroupSplatter
      $NewGroupCreated = $false
      try { if(Get-ADGroup -Filter "Name -like ""$($GroupInfo.GroupName)""") {$NewGroupCreated = $true}} catch { } #do nothing
      if($NewGroupCreated)
      {
        $GroupInfo.Status = "Complete"
      }
      else
      {
        $GroupInfo.Status = "Error"
      }
    }
    else
    {
      New-ADGroup @GroupSplatter
      $NewGroupCreated = $false
      try { if(Get-ADGroup -Filter "Name -like ""$($GroupInfo.GroupName)""") {$NewGroupCreated = $true}} catch { } #do nothing
      if($NewGroupCreated)
      {
        $GroupInfo.Status = "Complete"
        Write-Log "$ScriptFileName" "Group Created: $($GroupInfo.GroupName)" "Groups"
      }
      else
      {
        $GroupInfo.Status = "Error"
        Write-Log "$ScriptFileName" "ERROR - Failed to Create Group: $($GroupInfo.GroupName)" "Groups"
      }
    }
  }
}

function Remove-ADGroups($ADGroupsToRemove)
{
  $resultArray = @()
  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0
  Import-Module -Name "./Modules/MenuPrinter.psm1"


  foreach($group in $ADGroupsToRemove)
  {
    Write-Tagged ".." "Removing Group:  $($group.Name)"
    try { Remove-ADGroup $group -Confirm:$false } catch { }

    if(!(Get-ADGroup -Filter "Name -like ""$($group.Name)"""))
    {
      Write-Tagged "OK" "Removing Group:  $($group.Name)"
      Write-Log "$ScriptFileName" "Group Removed: $($group.Name)" "Groups"
      $resultArray += $true
    }
    else
    {
      Write-Tagged "ERROR" "Removing Group:  $($group.Name)"
      Write-Log "$ScriptFileName" "ERROR - Group NOT Removed: $($group.Name)" "Groups"
      $resultArray += $false
    }
  }

  if(!($resultArray.Contains($false)))
  {
    return $true
  }
  else
  {
    return $false
  }
}

function Search-ADGroups($QueryArray)
{
  $returnADGroups = @()
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"

  if($QueryArray -ne $null -and $QueryArray -ne "")
  {
    $ManagedOUInfo = "*,OU=$($configData.ShareGroupsOU),$($configData.DCPath)"

    foreach($query in $QueryArray)
    {
      $QueryGroups = Get-ADGroup -Filter "Name -like ""$query"""
      foreach($group in $QueryGroups)
      {
        if($($group.DistinguishedName) -like $ManagedOUInfo)
        {
          $returnADGroups += $group
        }
      }
    }
  }

  if($returnADGroups -eq $null -or $returnADGroups.Count -eq 0)
  {
    $returnADGroups = "None"
  }

  return $returnADGroups
}
