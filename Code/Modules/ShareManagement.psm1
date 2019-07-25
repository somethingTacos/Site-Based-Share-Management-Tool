function DisableInheritance
{
  param(
    $path,
    [switch] $CompareOnly
  )

  Import-Module -Name "./Modules/logging.psm1"

  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0

  if((Get-NTFSInheritance "$path" | select AccessInheritanceEnabled -ExpandProperty AccessInheritanceEnabled) -eq "True")
  {
    if($CompareOnly)
    {
      return $true
    }
    else
    {
      Disable-NTFSAccessInheritance "$path" -RemoveInheritedAccessRules
      Write-Log "$ScriptFileName" "Removed Inheritance from: $path" "Security"
    }
  }
  if($CompareOnly)
  {
    return $false
  }
}

function AddPermissions
{
  param(
    [string] $path,
    [string] $accountName,
    [string] $access,
    [switch] $CompareOnly,
    [switch] $CheckInheritance
  )

  Import-Module -Name "./Modules/logging.psm1"


  function permCheck($path, $accountName, $accesslevel)
  {
    $accessData = Get-NTFSAccess $path -EA SilentlyContinue
    $permissionsExist = $false
    $InheritanceEnabled = $false

    if($accessData -ne $null)
    {
      $permissions = ""
      switch($accesslevel)
      {
        "fullcontrol" { $permissions = "FullControl"}
        "traverse" { $permissions = "ReadAndExecute, Synchronize" }
        "modify" { $permissions = "ReadAndExecute, Write, Synchronize, DeleteSubdirectoriesAndFiles" }
      }

      $accessData | ForEach-Object {
        if($_.Account -eq "$accountName")
        {
          if($_.AccessRights -eq "$permissions")
          {
            if($accountName -eq $configData.FileServiceAdminGroup)
            {
              $InheritanceEnabled = DisableInheritance $path -CompareOnly
            }
            if(!($_.IsInherited))
            {
              $permissionsExist = $true
            }
          }
        }
      }
    }

    if($permissionsExist -and $InheritanceEnabled -eq $false)
    {
      return $true #true if perms exist
    }
    else
    {
      return $false #false if perms don't exist
    }
  }

  $permsExist = permCheck $path $accountName $access


  if(!($permsExist))
  {
    if($CompareOnly)
    {
      return $true #permissions need to be added
    }
    else
    {
      switch ($access)
      {
        "fullcontrol" { Add-NTFSAccess -Path "$path" -Account "$accountName" -AccessRights FullControl }
        "traverse" { Add-NTFSAccess -Path "$path" -Account "$accountName" -AccessRights ReadAndExecute, Synchronize }
        "modify" { Add-NTFSAccess -Path "$path" -Account "$accountName" -AccessRights ReadAndExecute, Write, Synchronize, DeleteSubdirectoriesAndFiles }
      }

      if($CheckInheritance)
      {
        DisableInheritance $path
      }

      $addSucceeded = permCheck $path $accountName $access
      $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0


      if($addSucceeded) { Write-Log "$ScriptFileName" "Added Permissions: $path :: $accountName :: $access" "Security" }

      return $addSucceeded
    }
  }
  else
  {
    if($CompareOnly)
    {
      return $false #permissions already exist
    }
  }
}

Function Compare-SiteFolders($path, $sites, $UnmanagedFolderNames)
{
  Write-Progress -Id 3 -Activity "Collecting Folder Data" -Status "Starting..." -PercentComplete 0
  $FoldersToAdd = @()


  $ExistingFoldersInfo = Get-CSVData "./Data/Folders.csv"
  $NewFoldersInfo = Get-CSVData "./Data/NewFolders.csv"

  $GeneralFolderCount = $ExistingFoldersInfo | Where { $_.hasgeneral -eq "1" } | measure | select Count -ExpandProperty Count

  $folderCount = dir $path | measure | select Count -ExpandProperty Count
  $workingFolderCount = $folderCount - $UnmanagedFolderNames.Count
  $siteCount = $sites | measure | select Count -ExpandProperty Count
  $ProgressMax = $workingFolderCount * $siteCount + $GeneralFolderCount
  $CompletedCount = 0
  $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)

  dir $path | ForEach-Object {
    $currentFolder = $_

    if(!($UnmanagedFolderNames.Contains($currentFolder.Name)))
    {
      if($CompletedCount -lt $ProgressMax)
      {
        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 3 -Activity "Collecting Folder Data" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $($currentFolder.FullName)\GENERAL"
      }

      foreach($folder in $ExistingFoldersInfo)
      {
        if($folder.name -eq $currentFolder.Name)
        {
          [bool]$HasGeneralFolder = [int]$folder.hasgeneral
          if($HasGeneralFolder)
          {
            #Check GENERAL folder
            $GeneralPath = $currentFolder.FullName + "\GENERAL"
            if(!(Test-Path($GeneralPath)))
            {
              $newFolderInfo = New-Object psobject
              $newFolderInfo | Add-Member -Type NoteProperty -Name "FolderName" -Value "GENERAL"
              $newFolderInfo | Add-Member -Type NoteProperty -Name "FolderPath" -Value $currentFolder.FullName
              $newFolderInfo | Add-Member -Type NoteProperty -Name "Status" -Value "Pending"
              $FoldersToAdd += $newFolderInfo
            }
          }
        }
      }

      foreach($folder in $NewFoldersInfo)
      {
        if($CompletedCount -lt $ProgressMax)
        {
          $CompletedCount += 1
          $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
          Write-Progress -Id 3 -Activity "Collecting Folder Data" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $($currentFolder.FullName)\GENERAL"
        }

        if($folder.name -eq $currentFolder.Name)
        {
          [bool]$HasGeneralFolder = [int]$folder.hasgeneral
          if($HasGeneralFolder)
          {
            #Check GENERAL folder
            $GeneralPath = $currentFolder.FullName + "\GENERAL"
            if(!(Test-Path($GeneralPath)))
            {
              $newFolderInfo = New-Object psobject
              $newFolderInfo | Add-Member -Type NoteProperty -Name "FolderName" -Value "GENERAL"
              $newFolderInfo | Add-Member -Type NoteProperty -Name "FolderPath" -Value $currentFolder.FullName
              $newFolderInfo | Add-Member -Type NoteProperty -Name "Status" -Value "Pending"
              $FoldersToAdd += $newFolderInfo
            }
          }
        }
      }

      $sites | ForEach-Object {
        $newFolderPath = $currentFolder.FullName + "\" + $_.Prefix

        if($CompletedCount -lt $ProgressMax)
        {
          $CompletedCount += 1
          $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
          Write-Progress -Id 3 -Activity "Collecting Folder Data" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $newFolderPath"
        }

        if(!(Test-Path($newFolderPath)))
        {
          $newFolderInfo = New-Object psobject
          $newFolderInfo | Add-Member -Type NoteProperty -Name "FolderName" -Value $_.Prefix
          $newFolderInfo | Add-Member -Type NoteProperty -Name "FolderPath" -Value $currentFolder.FullName
          $newFolderInfo | Add-Member -Type NoteProperty -Name "Status" -Value "Pending"
          $FoldersToAdd += $newFolderInfo
        }
      }
    }
  }

  Write-Progress -Id 3 -Activity "Collecting Folder Data" -Status "Done" -Completed

  return $FoldersToAdd
}

Function Compare-ShareSecurity
{
  param(
    $path,
    $sites,
    $UnmanagedFolderNames,
    [switch] $AddingFolders
  )

  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Starting..." -PercentComplete 0
  $SecurityToAdd = @()
  $FileServiceAdminGroup = $configData.FileServiceAdminGroup
  $GroupNamePrefix = $configData.GroupNamePrefix

  if($AddingFolders)
  {
    $KnownExistingFoldersInfo = Get-CSVData "./Data/Folders.csv"
    $KnownNewFoldersInfo = Get-CSVData "./Data/NewFolders.csv"
    $KnownFoldersInfo = $KnownExistingFoldersInfo + $KnownNewFoldersInfo
  }
  else
  {
    $KnownFoldersInfo = Get-CSVData "./Data/Folders.csv"
  }

  $GeneralFolderCount = $KnownFoldersInfo | Where { $_.hasgeneral -eq "1" } | measure | select Count -ExpandProperty Count


  function New-SecurityInfo($FolderPath, $GroupName, $AccessLevel)
  {
    $NewSecInfo = New-Object psobject
    $NewSecInfo | Add-Member -Type NoteProperty -Name "FolderPath" -Value $FolderPath
    $NewSecInfo | Add-Member -Type NoteProperty -Name "GroupName" -Value $GroupName
    $NewSecInfo | Add-Member -Type NoteProperty -Name "AccessLevel" -Value $AccessLevel
    $NewSecInfo | Add-Member -Type NoteProperty -Name 'Status' -Value "Pending"

    return $NewSecInfo
  }

  $folderCount = dir $path | measure | select Count -ExpandProperty Count
  $workingFolderCount = $folderCount - $UnmanagedFolderNames.Count
  $siteCount = $sites | measure | select Count -ExpandProperty Count
  $ProgressMax = ((($workingFolderCount * $siteCount) * 3) * 3) + ($siteCount * 3 * $GeneralFolderCount)
  $CompletedCount = 0
  $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)

  $sites | ForEach-Object {
    $currentSite = $_.Prefix
    dir $path | ForEach-Object {

      if(!($UnmanagedFolderNames.Contains($_.Name)))
      {
        if($GroupNamePrefix -ne $null -and $GroupNamePrefix -ne "")
        {
          $ModifyGroup = "$GroupNamePrefix $currentSite $_ MODIFY"
          $ReadOnlyGroup = "$GroupNamePrefix $currentSite $_ READONLY"
        }
        else
        {
          $ModifyGroup = "$currentSite $_ MODIFY"
          $ReadOnlyGroup = "$currentSite $_ READONLY"
        }

        $ModifyGroup = $ModifyGroup.ToUpper()
        $ReadOnlyGroup = $ReadOnlyGroup.ToUpper()

        $currentFolder = $_
        foreach($folder in $KnownFoldersInfo)
        {
          if($folder.name -eq $currentFolder.Name)
          {
            [bool]$HasGeneralFolder = [int]$folder.hasgeneral
            if($HasGeneralFolder)
            {
              #Check GENERAL folder
              $GeneralPath = $currentFolder.FullName + "\GENERAL"

              $CompletedCount += 1
              $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
              Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_ :: $FileServiceAdminGroup"
              $GenFSA_Add = AddPermissions $GeneralPath "$FileServiceAdminGroup" "fullcontrol" -CompareOnly

              $CompletedCount += 1
              $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
              Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_\GENERAL :: $ModifyGroup"
              $GenModify_Add = AddPermissions $GeneralPath $ModifyGroup "modify" -CompareOnly

              $CompletedCount += 1
              $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
              Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_ :: $ReadOnlyGroup"
              $GenReadOnly_Add = AddPermissions $GeneralPath $ReadOnlyGroup "traverse" -CompareOnly

              if($GenFSA_Add) { $SecurityToAdd += New-SecurityInfo "$GeneralPath" "$FileServiceAdminGroup" "fullcontrol" }
              if($GenModify_Add) { $SecurityToAdd += New-SecurityInfo "$GeneralPath" "$ModifyGroup" "modify" }
              if($GenReadOnly_Add) { $SecurityToAdd += New-SecurityInfo "$GeneralPath" "$ReadOnlyGroup" "traverse" }
            }
          }
        }

        #CHECK SHARE ROOT FOLDER
        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path :: FileServiceAdmins"
        $FSA1_Add = AddPermissions $path "$FileServiceAdminGroup" "fullcontrol" -CompareOnly

        if($FSA1_Add) { $SecurityToAdd += New-SecurityInfo $path "$FileServiceAdminGroup" "fullcontrol"}

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path :: $ModifyGroup"
        $MG1_Add = AddPermissions $path $ModifyGroup "traverse" -CompareOnly

        if($MG1_Add) { $SecurityToAdd += New-SecurityInfo $path $ModifyGroup "traverse"}

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path :: $ReadOnlyGroup"
        $RG1_Add = AddPermissions $path $ReadOnlyGroup "traverse" -CompareOnly

        if($RG1_Add) { $SecurityToAdd += New-SecurityInfo $path $ReadOnlyGroup "traverse"}
        #CHECK DEPARTMENT FOLDERS
        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_ :: FileServiceAdmins"
        $FSA2_Add = AddPermissions "$path\$_" "$FileServiceAdminGroup" "fullcontrol" -CompareOnly

        if($FSA2_Add) { $SecurityToAdd += New-SecurityInfo "$path\$_" "$FileServiceAdminGroup" "fullcontrol"}

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_ :: $ModifyGroup"
        $MG2_Add = AddPermissions "$path\$_" $ModifyGroup "traverse" -CompareOnly

        if($MG2_Add) { $SecurityToAdd += New-SecurityInfo "$path\$_" $ModifyGroup "traverse"}

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_ :: $ReadOnlyGroup"
        $RG2_Add = AddPermissions "$path\$_" $ReadOnlyGroup "traverse" -CompareOnly

        if($RG2_Add) { $SecurityToAdd += New-SecurityInfo "$path\$_" $ReadOnlyGroup "traverse"}
        #CHECK SITE FOLDERS
        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_\$currentSite :: FileServiceAdmins"
        $FSA3_Add = AddPermissions "$path\$_\$currentSite" "$FileServiceAdminGroup" "fullcontrol" -CompareOnly

        if($FSA3_Add) { $SecurityToAdd += New-SecurityInfo "$path\$_\$currentSite" "$FileServiceAdminGroup" "fullcontrol"}

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_\$currentSite :: $ModifyGroup"
        $MG3_Add = AddPermissions "$path\$_\$currentSite" $ModifyGroup "modify" -CompareOnly

        if($MG3_Add) { $SecurityToAdd += New-SecurityInfo "$path\$_\$currentSite" $ModifyGroup "modify"}

        $CompletedCount += 1
        $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
        Write-Progress -Id 4 -Activity "Collecting Security Data" -Status "Progress: $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Checking: $path\$_\$currentSite :: $ReadOnlyGroup"
        $RG3_Add = AddPermissions "$path\$_\$currentSite" $ReadOnlyGroup "traverse" -CompareOnly

        if($RG3_Add) { $SecurityToAdd += New-SecurityInfo "$path\$_\$currentSite" $ReadOnlyGroup "traverse"}
      }
    }
  }

  Write-progress -Id 4 -Activity "Collecting Security Data" -Status "Done" -Completed

  return $SecurityToAdd
}

function Add-SiteFolders($FoldersToAdd)
{
  Import-Module -Name "./Modules/logging.psm1"

  Write-Progress -Id 7 -Activity "Creating Site Folders" -Status "Starting..." -PercentComplete 0
  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0


  $ProgressMax = ($FoldersToAdd | measure | select Count -ExpandProperty Count)
  $CompletedCount = 0
  $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)

  #FoldersToAdd properties: [string]FolderName, [string]FolderPath, [string]Status
  ForEach($FolderInfo in $FoldersToAdd)
  {
    $fullPath = $FolderInfo.FolderPath + "\" + $FolderInfo.FolderName
    $CompletedCount += 1
    $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)

    Write-Progress -Id 7 -Activity "Creating Site Folders" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Creating: $fullPath"
    New-Item -ItemType Directory -Path "$fullPath" | Out-Null
    if(!(Test-Path("$fullPath")))
    {
      $FolderInfo.Status = "Error"
      Write-Log "$ScriptFileName" "ERROR - Folder NOT Created: $fullPath" "Folders"
    }
    else
    {
      $FolderInfo.Status = "Complete"
      Write-Log "$ScriptFileName" "Folder Created: $fullPath" "Folders"
    }
  }
  Write-Progress -Id 7 -Activity "Creating Site Folders" -Status "Done" -Completed

}

function Add-ShareSecurity($SecurityToAdd)
{
  Import-Module -Name "./Modules/logging.psm1"

  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  Write-Progress -Id 8 -Activity "Adding Security" -Status "Starting..." -PercentComplete 0

  $ProgressMax = ($SecurityToAdd | measure | select Count -ExpandProperty Count)
  $CompletedCount = 0
  $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)

  #SecurityToAdd properties: [string]FolderPath, [string]GroupName, [string]AccessLevel, [string]Status
  ForEach($SecurityInfo in $SecurityToAdd)
  {
    $CompletedCount += 1
    $PercentComplete = [math]::floor(($CompletedCount / $ProgressMax) * 100)
    Write-Progress -Id 8 -Activity "Adding Share Security" -Status "Progress:  $PercentComplete%" -PercentComplete $PercentComplete -CurrentOperation "Adding Permissions: $($SecurityInfo.FolderPath) :: $($SecurityInfo.GroupName)"

    if($SecurityInfo.GroupName -eq $configData.FileServiceAdminGroup)
    {
      AddPermissions $SecurityInfo.FolderPath $SecurityInfo.GroupName $SecurityInfo.AccessLevel -CheckInheritance | Out-Null
    }
    else
    {
      AddPermissions $SecurityInfo.FolderPath $SecurityInfo.GroupName $SecurityInfo.AccessLevel | Out-Null
    }

    $SecurityAddFailed = AddPermissions $SecurityInfo.FolderPath $SecurityInfo.GroupName $SecurityInfo.AccessLevel -CompareOnly

    if(!($SecurityAddFailed))
    {
      $SecurityInfo.Status = "Complete"
    }
    else
    {
      $SecurityInfo.Status = "Error"
    }
  }
  Write-Progress -Id 8 -Activity "Adding Security" -Status "Done" -Completed
}

function Remove-SharePermissions($SecurityGroups)
{
  Import-Module -Name "./Modules/logging.psm1"
  Import-Module -Name "./Modules/MenuPrinter.psm1"

  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"

  function RemoveAccess($AccessInfo, $dir)
  {
    $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0

    if($AccessInfo -ne $null)
    {
      foreach($access in $AccessInfo)
      {
        $accountName = $access.Account.AccountName.Split('\')[1]

        if($SecurityGroups.Contains($accountName))
        {
          Write-Tagged ".." "Removing Permissions: $dir :: $($accountName)"

          Remove-NTFSAccess -Path $dir -Account $access.Account -AccessRights $access.AccessRights

          $Check = $null
          $Check = Get-NTFSAccess -Path $dir -Account $access.Account
          if($Check -ne $null)
          {
            Write-Tagged "ERROR" "Removing Permissions: $dir :: $($accountName)"
            Write-Log "$ScriptFileName" "ERROR - Permissions NOT Removed: $dir :: $($access.Account.AccountName)" "Security"
          }
          else
          {
            Write-Tagged "OK" "Removing Permissions: $dir :: $($accountName)"
            Write-Log "$ScriptFileName" "Permissions Removed: $dir :: $($access.Account.AccountName)" "Security"
          }
        }
      }
    }
  }

  if($SecurityGroups -ne $null -and $SecurityGroups -ne "")
  {
    dir $configData.ShareFolderRootPath | ForEach-Object {
      $currentFolder = $_
      dir $currentFolder.FullName | ForEach-Object {
        $currentSubFolder = $_
        $SubFolderAccess = Get-NTFSAccess $currentSubFolder.FullName
        RemoveAccess $SubFolderAccess $currentSubFolder.FullName
      }
      #NOTE - Check Dept Folder
      $FolderAccess = Get-NTFSAccess $currentFolder.FullName
      RemoveAccess $FolderAccess $currentFolder.FullName
    }
    #NOTE - Check ShareRoot
    $ShareRootAccess = Get-NTFSAccess $configData.ShareFolderRootPath
    RemoveAccess $ShareRootAccess $configData.ShareFolderRootPath
  }
}
