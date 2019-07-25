Function Compare-ADGroups($path, $sites, $UnmanagedFolderNames)
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $GroupsToAdd = @()

  $cred = Get-Credential

  $remoteServer = $configData.RemoteADDC
  $sess = New-PSSession -Credential $cred -ComputerName "$remoteServer"

  if($sess)
  {
    Invoke-Command $sess -Scriptblock { ImportSystemModules }

    Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Starting..." -PercentComplete 0
    $folderCount = dir $path | measure | select Count -ExpandProperty Count
    $workingFolderCount = $folderCount - $UnmanagedFolderNames.Count

    $ExistingFolderInfo = Get-CSVData "./Data/Folders.csv"
    $GeneralFolderCount = $ExistingFolderInfo | Where { $_.hasgeneral -eq "1" } | measure | select Count -ExpandProperty Count

    $siteCount = $sites | measure | select Count -ExpandProperty Count
    $ProgressMax = $workingFolderCount * $siteCount * 2
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

          $scriptBlock = {
            $returnValue = $false
            try
            {
              if(Get-ADGroup "$args")
              {
                $returnValue = $true
              }
            }
            catch {  } #do nothing
            return $returnValue
          }

          if($CompletedCount -lt $ProgressMax + 1)
          {
            $CompletedCount += 1
            $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
            Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $ModifyGroupToCheck"
          }

          if(!(Invoke-Command -Session $sess -ArgumentList $ModifyGroupToCheck -Scriptblock $scriptBlock))
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

          if(!(Invoke-Command -Session $sess -ArgumentList $ReadOnlyGroupToCheck -Scriptblock $scriptBlock))
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
  }

  try
  {
    Remove-PSSession $sess
  }
  catch { $GroupsToAdd = "Error" }

  Write-Progress -Id 2 -Activity "Collecting Group Data" -Status "Done" -Completed

  return $GroupsToAdd
}

function Add-ADGroups($GroupsToAdd)
{
  Import-Module -Name "./Modules/logging.psm1"
  $global:RemoteAuthError = $false
  Write-Progress -Id 6 -Activity "Creating AD Groups" -Status "Starting..." -PercentComplete 0
  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0

  $ProgressMax = ($GroupsToAdd | measure | select Count -ExpandProperty Count)
  $CompletedCount = 0
  $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)

  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"

  $cred = Get-Credential

  $remoteServer = $configData.RemoteADDC
  $sess = New-PSSession -Credential $cred -ComputerName "$remoteServer"

  if($sess)
  {
    Invoke-Command $sess -Scriptblock { ImportSystemModules }

    #GroupsToAdd Properties: [string]GroupName, [string]GroupOU, [string]Status
    ForEach($GroupInfo in $GroupsToAdd)
    {
      $GroupSplatter = @{
        Name = "$($GroupInfo.GroupName)"
        GroupCategory = 'Security'
        GroupScope = 'Global'
        SamAccountName = "$($GroupInfo.GroupName)"
        Description = "A Company Share Security Group"
        Path = "$($GroupInfo.GroupOU)"
      }

      $CheckOU_ScriptBlock = {
        $returnValue = $false
        try
        {
          if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""$args""")
          {
            $returnValue = $true
          }
        }
        catch {  } #do nothing
        return $returnValue
      }

      $AddOU_ScriptBlock = {
        param(
          $OUSplatter
        )

        try
        {
          New-ADOrganizationalUnit @OUSplatter
        }
        catch { } #do nothing
      }

      $CheckGroup_ScriptBlock = {
        $returnValue = $false
        try
        {
          if(Get-ADGroup -Filter "Name -like ""$args""")
          {
            $returnValue = $true
          }
        }
        catch {  } #do nothing
        return $returnValue
      }

      $AddGroup_SriptBlock = {
        param(
          $GroupSplatter
        )
        try
        {
          New-ADGroup @GroupSplatter
        }
        catch {  } #do nothing
      }

      if(!(Invoke-Command -Session $sess -ArgumentList $GroupInfo.GroupOU -Scriptblock $CheckOU_ScriptBlock))
      {
        #OUPath was not found. Check Site OU
        $dnArray = $GroupInfo.GroupOU.Split(',')
        $SiteDNArray = $dnArray[1..$($dnArray.Count)]
        $SiteOU = [System.String]::Join(',',$SiteDNArray)

        if(!(Invoke-Command -Session $sess -ArgumentList $SiteOU -Scriptblock $CheckOU_ScriptBlock))
        {
          if($configData.GroupNamePrefix -ne "")
          {
            $SitePrefix = $GroupInfo.GroupName.Split(' ') | select -Index 1
          }
          else
          {
            $SitePrefix = $GroupInfo.GroupName.Split(' ') | select -Index 0
          }


          $SiteOUPath = "OU=$($configData.ShareGroupsOU),$($configData.DCPath)"
          $OUSplatter = @{
            Name = "$SitePrefix"
            Path = "$SiteOUPath"
          }

          Invoke-Command -Session $sess -ArgumentList $OUSplatter -Scriptblock $AddOU_ScriptBlock

          if(!(Invoke-Command -Session $sess -ArgumentList $SiteOU -Scriptblock $CheckOU_ScriptBlock))
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
        $OUSplatter = @{
          Name = "$AccessOUName"
          Path = "$SiteOU"
        }

        Invoke-Command -Session $sess -ArgumentList $OUSplatter -Scriptblock $AddOU_ScriptBlock

        if(!(Invoke-Command -Session $sess -ArgumentList $GroupInfo.GroupOU -Scriptblock $CheckOU_ScriptBlock))
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

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 6 -Activity "Creating AD Groups" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Creating: $($GroupInfo.GroupName)"

        Invoke-Command -Session $sess -ArgumentList $GroupSplatter -Scriptblock $AddGroup_SriptBlock

        if(Invoke-Command -Session $sess -ArgumentList $GroupInfo.GroupName -Scriptblock $CheckGroup_ScriptBlock)
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
      else
      {
        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 6 -Activity "Creating AD Groups" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Creating: $($GroupInfo.GroupName)"
        Invoke-Command -Session $sess -ArgumentList $GroupSplatter -Scriptblock $AddGroup_SriptBlock

        if(Invoke-Command -Session $sess -ArgumentList $GroupInfo.GroupName -Scriptblock $CheckGroup_ScriptBlock)
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
  try
  {
    Remove-PSSession $sess
  }
  catch { $global:RemoteAuthError = $true } #session couldn't start

  Write-Progress -Id 6 -Activity "Creating AD Groups" -Status "Done" -Completed
}

function Remove-ADGroups($ADGroupToRemove, $cred)
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  Import-Module -Name "./Modules/logging.psm1"
  Import-Module -Name "./Modules/MenuPrinter.psm1"
  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0


  $remoteServer = $configData.RemoteADDC
  $sess = New-PSSession -Credential $cred -ComputerName "$remoteServer"

  if($sess)
  {
    Invoke-Command $sess -Scriptblock { ImportSystemModules }

    $RemoveADGroup_ScriptBlock = {
      param(
        $group
      )

      try
      {
        try { Get-ADGroup -Filter "Name -like ""$($group.Name)""" | Remove-ADGroup -Confirm:$false } catch { }

        if(!(Get-ADGroup -Filter "Name -like ""$($group.Name)"""))
        {
          return $true
        }
        else
        {
          return $false
        }
      }
      catch { return $false } #do nothing
    }

    $resultArray = @()

    foreach($group in $ADGroupToRemove)
    {
      $Succeeded = $false
      Write-Tagged ".." "Removing Group:  $($group.Name)"
      $Succeeded += Invoke-Command -Session $sess -ArgumentList $group -Scriptblock $RemoveADGroup_ScriptBlock
      $resultArray += $Succeeded

      if($Succeeded)
      {
        Write-Tagged "OK" "Removing Group:  $($group.Name)"
        Write-Log "$ScriptFileName" "Group Removed: $($group.Name)" "Groups"
      }
      else
      {
        Write-Tagged "ERROR" "Removing Group:  $($group.Name)"
        Write-Log "$ScriptFileName" "ERROR - Group NOT Removed: $($group.Name)" "Groups"
      }
    }
  }

  try
  {
    Remove-PSSession $sess
  }
  catch { return $false }

  if(!($resultArray.Contains($false)))
  {
    return $true
  }
  else
  {
    return $false
  }
}

function Search-ADGroups($QueryArray, $cred)
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $returnADGroups = @()

  $remoteServer = $configData.RemoteADDC
  $sess = New-PSSession -Credential $cred -ComputerName "$remoteServer"

  if($sess)
  {
    Invoke-Command $sess -Scriptblock { ImportSystemModules }

    $GetADGroups_ScriptBlock = {
      param(
        $QueryArray,
        $ManagedOUInfo
      )
      $QueryArray = $QueryArray.Split('>')
      $returnGroups = @()

      try
      {
        if($QueryArray -ne $null -and $QueryArray -ne "")
        {
          foreach($query in $QueryArray)
          {
            $QueryGroups = Get-ADGroup -Filter "Name -like ""$query"""
            foreach($group in $QueryGroups)
            {
              if($($group.DistinguishedName) -like $ManagedOUInfo)
              {
                $returnGroups += $group
              }
            }
          }
        }
      }
      catch { } #do nothing
      return $returnGroups
    }

    if($QueryArray.Count -gt 1)
    {
      $stupidFix = [System.String]::Join(">", $QueryArray)
    }
    else
    {
      $stupidFix = $QueryArray
    }

    $managedOuInfo = "*,OU=$($configData.ShareGroupsOU),$($configData.DCPath)"

    $returnADGroups = @() #WARNING - Having issues with remote returns, not sure why.
    $returnADGroups = Invoke-Command -Session $sess -ArgumentList $stupidFix,$managedOuInfo -Scriptblock $GetADGroups_ScriptBlock

  }

  try
  {
    Remove-PSSession $sess
  }
  catch { $returnADGroups = "Error" }

  if($returnADGroups -eq $null -or $returnADGroups -eq "")
  {
    $returnADGroups = "None"
  }

  return $returnADGroups
}
