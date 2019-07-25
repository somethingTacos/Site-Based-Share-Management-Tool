$result = ""
Import-Module -Name "./Modules/MenuPrinter.psm1"
Import-Module -Name "./Modules/ShareData.psm1"
Import-Module -Name "./Modules/logging.psm1"
$configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | Select -index 0
$options = "Add New Department Folder","Commit New Department Folders","Clear New Folders","Back to main menu"
$NoDepartmentFolders = $true
$ExistingFolderNames = ""
$NewFolderNames = ""
$UnmanagedFolderNames = Get-UnmanagedFolderNames $configData.ShareFolderRootPath
$MissingDeptFoldersFound = $false

Clear
PrintMenuHeader $configData.MainMenuTitle $configData.ShareFolderRootPath

$ExistingFolders = Get-CSVData "./Data/Folders.csv"
$NewFolders = Get-CSVData "./Data/NewFolders.csv"

if($ExistingFolders -ne $null -and $ExistingFolders -ne "")
{
  Write-Host "Existing Department Folders:"
  $offset = Get-PrintOffset $ExistingFolders


  ForEach($folder in $ExistingFolders)
  {
    $deptFolderPath = $configData.ShareFolderRootPath + "\" + $folder.name
    if(Compare-DepartmentFolder $deptFolderPath)
    {
      PrintFolderData $folder.name $folder.hasgeneral $offset
    }
    else
    {
      $MissingDeptFoldersFound = $true
      PrintFolderData $folder.name $folder.hasgeneral $offset -IsMissing
    }
  }

  PrintHeaderLine $configData.MainMenuTitle
  $NoDepartmentFolders = $false
}

if($NewFolders -ne $null -and $NewFolders -ne "")
{
  Write-Host "New Department Folders:"
  $offset = Get-PrintOffset $NewFolders

  ForEach($folder in $NewFolders) { PrintFolderData $folder.name $folder.hasgeneral $offset -IsNew }

  PrintHeaderLine $configData.MainMenuTitle
  $NoDepartmentFolders = $false
}

if($UnmanagedFolderNames -ne $null -and $UnmanagedFolderNames.Count -ne 0)
{
  Write-Host "Unmanaged Folders:"
  ForEach($value in $UnmanagedFolderNames.Values)
  {
    Write-Host "FolderName: " -nonewline
    Write-Host "$value" -Foregroundcolor Red
  }
  PrintHeaderLine $configData.MainMenuTitle
  $NoDepartmentFolders = $false
}

if($NoDepartmentFolders)
{
  Write-Host "No Department Folders Exist  :("
}

Write-Host ""
Write-Host "1) Add New Department Folder  -  2) Commit New Department Folders  -  3) Clear New Folders  -  4) Back to main menu"

if($MissingDeptFoldersFound)
{
  Write-Host "- - - ISSUES - - -" -Foregroundcolor Red
  Write-Warning "Missing department folders were found! Please restore them or type 'remove missing folders' without quotes"
  Write-Host "       : to remove ALL missing folders from management (group removal will be attempted!)" -Foregroundcolor yellow
}

if($UnmanagedFolderNames -ne $null -and $UnmanagedFolderNames.Count -ne 0)
{
  Write-Host "- - - Other - - -" -Foregroundcolor Red
  Write-Host "Unamanged folders can be added by typing 'add umfs' without quotes" -Foregroundcolor Yellow
  if($MissingDeptFoldersFound)
  {
    $result = Get-UserSelection $options $ScriptFileName -allow_umfs -allow_rmfs
  }
  else
  {
    $result = Get-UserSelection $options $ScriptFileName -allow_umfs
  }
}
else
{
  if($MissingDeptFoldersFound)
  {
    $result = Get-UserSelection $options $ScriptFileName -allow_rmfs
  }
  else
  {
    $result = Get-UserSelection $options $ScriptFileName
  }
}

return $result
