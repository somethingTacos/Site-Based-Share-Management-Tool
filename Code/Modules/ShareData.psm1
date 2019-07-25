function Get-CSVData($path)
{
  if((Test-Path("$path")) -eq $true)
  {
    #load site Data
    $CSVData = Import-CSV "$path"
    return $CSVData
  }
}

function Save-CSVData
{
  param(
    $ObjectName,
    $additionalData, #Either a Site Prefix string or General folder boolean
    $dataType
  )

  Import-Module -Name "./Modules/logging.psm1"

  $dataFile = ""

  switch($dataType)
  {
    "Sites" { $dataFile = "./Data/Sites.csv" }
    "NewSites" { $dataFile = "./Data/NewSites.csv" }
    "Folders" { $dataFile = "./Data/Folders.csv" }
    "NewFolders" { $dataFile = "./Data/NewFolders.csv" }
  }

  $data = Get-CSVData "$dataFile"

  if($additionalData.GetType() -eq [string])
  {
    if($data -ne $Null -and $data -ne "")
    {
      $dataToAdd = New-Object PsObject -Property @{ name = "$ObjectName" ; prefix = "$additionalData" }
      $data = [Array]$data + $dataToAdd
    }
    else
    {
      $data = New-Object PsObject -Property @{ name = "$ObjectName" ; prefix = "$additionalData" }
    }
  }

  if($additionalData.GetType() -eq [bool])
  {
    if($data -ne $Null -and $data -ne "")
    {
      $dataToAdd = New-Object PsObject -Property @{ name = "$ObjectName" ; hasgeneral = "$([int]$additionalData)" }
      $data = [Array]$data + $dataToAdd
    }
    else
    {
      $data = New-Object PsObject -Property @{ name = "$ObjectName" ; hasgeneral = "$([int]$additionalData)" }
    }
  }

  $data | Export-CSV "$dataFile"
}

function Compare-SiteName($SiteName)
{
  $ExistingSites = Get-CSVData "./Data/Sites.csv"
  $NewSites = Get-CSVData "./Data/NewSites.csv"

  Foreach($site in $ExistingSites) {
    if($site.name.ToUpper() -eq $SiteName.ToUpper())
    {
      return $true
    }
  }
  Foreach($site in $NewSites) {
    if($site.name.ToUpper() -eq $SiteName.ToUpper())
    {
      return $true
    }
  }

  return $false
}

function Compare-SitePrefix($SitePrefix)
{
  $ExistingSites = Get-CSVData "./Data/Sites.csv"
  $NewSites = Get-CSVData "./Data/NewSites.csv"

  Foreach($site in $ExistingSites) {
    if($site.prefix.ToUpper() -eq $SitePrefix.ToUpper())
    {
      return $true
    }
  }
  Foreach($site in $NewSites) {
    if($site.prefix.ToUpper() -eq $SitePrefix.ToUpper())
    {
      return $true
    }
  }
  return $false
}

function Compare-FolderName($NewFolderName)
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $ExistingFolderNames = dir $configData.ShareFolderRootPath | select Name -ExpandProperty Name
  $NewFolderNames = Get-CSVData "./Data/NewFolders.csv"

  if($ExistingFolderNames -ne $null -and $ExistingFolderNames -ne "")
  {
    foreach($folderName in $ExistingFolderNames)
    {
      if($folderName -eq $NewFolderName)
      {
        return $true
      }
    }
  }

  if($NewFolderNames -ne $null -and $NewFolderNames -ne "")
  {
    foreach($folder in $NewFolderNames)
    {
      if($folder.name -eq $NewFolderName)
      {
        return $true
      }
    }
  }
  return $false
}

function Compare-DepartmentFolder($DeptFolderPath)
{
  if(!(Test-Path($DeptFolderPath)))
  {
    return $false
  }
  return $true
}

function Add-UnmanagedFolders
{
  Clear
  Import-Module -Name "./Modules/ShareData.psm1"
  Import-Module -Name "./Modules/logging.psm1"
  
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $UnmanagedFolderNames = Get-UnmanagedFolderNames $configData.ShareFolderRootPath
  $ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0


  foreach($folderName in $UnmanagedFolderNames.Values)
  {
    Write-Host ""
    $addFolder = Read-Host("Add: $($folderName)? (Y/[N])")
    $HasGeneral = $false

    if($addFolder -eq "Y" -or $addFolder -eq "y")
    {
      Write-Host "$folderName General Folder: " -nonewline
      $folderGeneralPath = $configData.ShareFolderRootPath + "\" + $folderName + "\GENERAL"
      if((Test-Path($folderGeneralPath)))
      {
        Write-Host "found" -Foregroundcolor green
      }
      else
      {
        Write-Host "None"
      }
      $useGeneral = Read-Host("Use GENERAL folder? (Y/[N])")
      if($useGeneral -eq "Y" -or $useGeneral -eq "y")
      {
        $HasGeneral = $true
      }

      Save-CSVData $folderName $HasGeneral "NewFolders"
      Write-Log "$ScriptFileName" "Umanaged Folder added - Name: $folderName  Has General: $HasGeneral" "Folders"
    }
  }
}

function Read-FolderData($SendingFile)
{
  Clear
  Import-Module -Name "./Modules/MenuPrinter.psm1"
  Import-Module -Name "./Modules/logging.psm1"

  $NewFolderName = ""
  $HasGeneral = $false
  $invalidEntry = $true

  do
  {
    Clear
    Write-Host "-- Adding New Deparment Folder --"
    Write-Host ""
    $NewFolderName = Read-Host("Enter a new folder name")
    $NewFolderName = $NewFolderName -replace '[^a-zA-Z0-9 ]',''
    $invalidEntry = Compare-FolderName $NewFolderName
    if($invalidEntry)
    {
      Write-Host "Name already in use!" -Foregroundcolor Red
      PressEnterToContinue
    }
  }
  until(!($invalidEntry))

  if($NewFolderName -ne $null -and $NewFolderName -ne "")
  {
    $NewFolderName = $NewFolderName.Trim()
    Clear
    Write-Host "-- Adding New Deparment Folder --"
    Write-Host "New Folder Name: '" -nonewline
    Write-Host "$NewFolderName" -nonewline -Foregroundcolor Cyan
    Write-Host "'"
    Write-Host ""
    $hasGeneralFolder = Read-Host("Add a GENERAL folder? (Y/[N])")

    if($hasGeneralFolder -eq "Y" -or $hasGeneralFolder -eq "y")
    {
      $HasGeneral = $true
    }

    Clear
    Write-Host "-- Adding New Deparment Folder --"
    Write-Host "New Folder Name: '" -nonewline
    Write-Host "$($NewFolderName)" -nonewline -Foregroundcolor Cyan
    Write-Host "'"
    Write-Host ""
    Write-Host "Has GENERAL folder: '" -nonewline
    Write-Host "$([bool]$HasGeneral)" -nonewline -Foregroundcolor Cyan
    Write-Host "'"
    Write-Host ""

    $confirmAdd = Read-Host("Add above folder info? (Y/[N])")
    if($confirmAdd -eq "Y" -or $confirmAdd -eq "y")
    {
      Save-CSVData "$NewFolderName" $HasGeneral "NewFolders"

      Write-Log "$SendingFile" "Valid New Folder Name: $NewFolderName" "Program"
      Write-Log "$SendingFile" "New Folder Has General: $([int]$HasGeneral)" "Program"
      Write-Host "-- New Folder Info Saved --" -Foregroundcolor Green
      PressEnterToContinue
    }
    else
    {
      Write-Log "$SendingFile" "Add Aborted" "Program"
      Write-Host "Add Aborted!" -Foregroundcolor Red
      PressEnterToContinue
    }
  }
  else
  {
    Write-Host "Cannot add null name! Aborting add!" -Foregroundcolor Red
    PressEnterToContinue
  }
}

function Read-SiteData($SendingFile)
{
  Import-Module -Name "./Modules/MenuPrinter.psm1"
  Import-Module -Name "./Modules/logging.psm1"

  $SiteName = ""
  $SitePrefix = ""

  [bool]$invalidEntry = $true
  do
  {
    Clear
    Write-Host "-- Adding New Site --"
    $SiteName = Read-Host("Enter the site name - Example: Test Site")
    $SiteName = $SiteName -replace '[^a-zA-Z0-9 ]',''
    $invalidEntry = Compare-SiteName $SiteName
    if($invalidEntry)
    {
      Write-Host "Entry Exists!" -Foregroundcolor Red
      PressEnterToContinue
    }
  }
  until(!($invalidEntry))

  Write-Log "$SendingFile" "Valid New Site Name: $SiteName" "Program"
  [bool]$invalidEntry = $true

  do
  {
    Clear
    Write-Host "-- Adding New Site --"
    Write-Host "New Site Name: " -nonewline
    Write-Host $SiteName -Foregroundcolor Cyan
    Write-Host ""
    $SitePrefix = Read-Host("Enter the site prefix - Example: TST")
    $invalidEntry = Compare-SitePrefix $SitePrefix
    if($invalidEntry)
    {
      Write-Host "Entry Exists!" -Foregroundcolor Red
      PressEnterToContinue
    }
  }
  until(!($invalidEntry))

  $SitePrefix = $SitePrefix.ToUpper()
  $SitePrefix = $SitePrefix -replace '[^a-zA-Z0-9]',''
  Write-Log "$SendingFile" "Valid New Site Prefix: $SitePrefix" "Program"

  Clear
  Write-Host "-- Adding New Site --"
  Write-Host "New Site Name: " -nonewline
  Write-Host $SiteName -Foregroundcolor Cyan
  Write-Host ""
  Write-Host "New Site Prefix: " -nonewline
  Write-Host $SitePrefix -Foregroundcolor Cyan
  Write-Host ""
  if($SiteName -ne "" -and $SitePrefix -ne "")
  {
    $confirmAdd = Read-Host("Add above site info? (Y/[N])")
    if($confirmAdd -eq "Y" -or $confirmAdd -eq "y")
    {
      #save to NewSites.csv
      Save-CSVData $SiteName $SitePrefix.ToUpper() "NewSites"
      Write-Log "$SendingFile" "New Site Info Saved" "Program"
      Write-Host "-- New Site Info Saved --" -Foregroundcolor Green
      PressEnterToContinue
    }
    else
    {
      #don't save, exit operation
      Write-Log "$SendingFile" "Add Aborted" "Program"
      Write-Host "Add Aborted!" -Foregroundcolor Red
      PressEnterToContinue
    }
  }
  else
  {
    Write-Log "$SendingFile" "Cannot add site with empty field - add aborted" "Program"
    Write-Host "Cannot add site with empty field! - add aborted" -Foregroundcolor Red
    PressEnterToContinue
  }
}

function Get-UnmanagedFolderNames($path)
{
  Import-Module -Name "./Modules/ShareData.psm1"
  $hashTable = @{}
  $UnmanagedFolderNames = dir $path | select Name -ExpandProperty Name
  $UnmanagedFolderNames | foreach { $hashTable[$_] = $_ }
  $ExistingFolders = Get-CSVData "./Data/Folders.csv"
  $NewFolders = Get-CSVData "./Data/NewFolders.csv"

  if($ExistingFolders -ne $null -and $ExistingFolders -ne "")
  {
    $ExistingFolders | foreach { if($hashTable.Contains($_.name)) {$hashTable.Remove($_.name) } }
  }

  if($NewFolders -ne $null -and $NewFolders -ne "")
  {
    $NewFolders | foreach { if($hashTable.Contains($_.name)) {$hashTable.Remove($_.name) } }
  }

  if($hashTable -ne $null)
  {
    return $hashTable
  }
  else
  {
    return ""
  }
}

function Remove-MissingDeptFolders #NOTE - Need to remove all groups permissions before delete groups from AD to avoid orphaned group permissions.
{
  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  Import-Module -Name "./Modules/ShareData.psm1"
  Import-Module -Name "./Modules/ShareManagement.psm1"
  Import-Module -Name "./Modules/MenuPrinter.psm1"
  Import-Module -Name "./Modules/logging.psm1"

  $cred = ""

  [bool]$IsADDC = [int]$configData.IsADDC

  if($IsADDC)
  {
    Import-Module -Name "./Modules/LOCAL_AD.psm1"
  }
  else
  {
    Import-Module -Name "./Modules/REMOTE_AD.psm1"
    $cred = Get-Credential
  }

  $ExistingFolders = Get-CSVData "./Data/Folders.csv"
  $newExistingFolders = @()
  $removelist = @()

  $dirOutput = dir $configData.ShareFolderRootPath | select Name -ExpandProperty Name

  if($dirOutput -ne $null)
  {
    $newExistingFolders = $ExistingFolders | Where { ($dirOutput.Contains($_.name)) }
    $removeList = $ExistingFolders | Where { !($dirOutput.Contains($_.name)) }
  }
  else
  {
    $removeList = $ExistingFolders | select name -ExpandProperty name
  }

  $removeQueryList = @()
  $removeQueryList = $removeList | foreach { return "$($configData.GroupNamePrefix) * $($_.name) *" }

  $GroupsToRemove = Search-ADGroups $removeQueryList $cred

  if($GroupsToRemove -eq "Error")
  {
    Write-Host ""
    Write-Warning "Server or Authentication Issue. Could not get AD groups to remove."
  }
  elseif($GroupsToRemove -eq "None")
  {
    Remove-Item "./Data/Folders.csv"
    if($dirOutput -ne $null)
    {
      foreach($folder in $newExistingFolders)
      {
        [bool]$HasGeneral = [int]$folder.hasgeneral
        Save-CSVData $folder.name $HasGeneral "Folders"
      }
    }

    Write-Host "No groups needed to be removed."
  }
  else
  {
    Clear
    Write-Host "Here is a list of AD Groups that can be removed:"
    $GroupsToRemove | foreach { Write-Host $_.Name }
    Write-Host ""
    $removeNow = Read-Host "Remove these groups now? (Y/[N])"
    if($removeNow -eq "Y" -or $removeNow -eq "y")
    {
      $GroupNames = $GroupsToRemove | foreach { $_.Name }
      Write-Host "Starting Permissions Removal..." -Foregroundcolor Yellow
      Remove-SharePermissions $GroupNames
      Write-Host "Starting Group Removal..." -Foregroundcolor Yellow
      $Complete = Remove-ADGroups $GroupsToRemove $cred

      if($Complete)
      {
        Remove-Item "./Data/Folders.csv"
        if($dirOutput -ne $null)
        {
          foreach($folder in $newExistingFolders)
          {
            [bool]$HasGeneral = [int]$folder.hasgeneral
            Save-CSVData $folder.name $HasGeneral "Folders"
          }
        }
      }
      else
      {
        Write-Host ""
        Write-Warning "Server or Authentication Error, Could not remove groups. Aborting Operation."
      }
    }
  }

  PressEnterToContinue
}

function Remove-NonCommitedData
{
  param(
    $SendingFile,
    [switch] $SiteData,
    [switch] $FolderData
  )
  Import-Module -Name "./Modules/MenuPrinter.psm1"
  Import-Module -Name "./Modules/logging.psm1"

  if($SiteData)
  {
    if((Test-Path("./Data/NewSites.csv")) -eq $True)
    {
      Write-Host "-- You are about to delete all New Site data --" -Foregroundcolor Red
      $confirmClear = Read-Host("Type 'Clear New Sites' to confirm this action")

      if($confirmClear -eq "Clear New Sites")
      {
        Remove-Item "./Data/NewSites.csv"
        Write-Log "$SendingFile" "New Site Data was deleted" "Program"
      }
      else
      {
        Write-Host "Operation Aborted" -Foregroundcolor Red
        Write-Log "$SendingFile" "Operation Aborted" "Program"
        PressEnterToContinue
      }
    }
    else
    {
      Write-Host "No New Sites Exist"
      Write-Log "$SendingFile" "No New Sites Exist" "Program"
      PressEnterToContinue
    }
  }

  #--------------------------------------------------------------------------
  if($FolderData)
  {
    if((Test-Path("./Data/NewFolders.csv")) -eq $True)
    {
      Write-Host "-- You are about to delete all New Folder data --" -Foregroundcolor Red
      $confirmClear = Read-Host("Type 'Clear New Folders' to confirm this action")

      if($confirmClear -eq "Clear New Folders")
      {
        Remove-Item "./Data/NewFolders.csv"
        Write-Log "$SendingFile" "New Folder Data was deleted" "Program"
      }
      else
      {
        Write-Host "Operation Aborted" -Foregroundcolor Red
        Write-Log "$SendingFile" "Operation Aborted" "Program"
        PressEnterToContinue
      }
    }
    else
    {
      Write-Host "No New Folders Exist"
      Write-Log "$SendingFile" "No New Folders Exist" "Program"
      PressEnterToContinue
    }
  }
}
