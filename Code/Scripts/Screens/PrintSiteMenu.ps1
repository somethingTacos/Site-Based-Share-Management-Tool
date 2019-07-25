$result = ""
Import-Module -Name "./Modules/MenuPrinter.psm1"
Import-Module -Name "./Modules/ShareData.psm1"
Import-Module -Name "./Modules/logging.psm1"
$configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | Select -index 0
$options = "Add New Site","Commit New Sites","Clear New Sites","Back to main menu","Remove Site"
$ExistingSites = ""
$NewSites = ""
$NoSiteData = $true

$ExistingSites = Get-CSVData "./Data/Sites.csv"
$NewSites = Get-CSVData "./Data/NewSites.csv"

#start printing menu
Clear
PrintMenuHeader $configData.MainMenuTitle $configData.ShareFolderRootPath

if($ExistingSites -ne "" -and $ExistingSites -ne $Null)
{
  Write-Host "Existing Sites:"
  $offset = Get-PrintOffset $ExistingSites
  forEach($site in $ExistingSites) {
    PrintSiteData $site.name $site.prefix $offset
  }
  PrintHeaderLine $configData.MainMenuTitle
  $NoSiteData = $false
}

if($NewSites -ne "" -and $NewSites -ne $Null)
{
  Write-Host "New Sites:"
  $offset = Get-PrintOffset $NewSites
  forEach($site in $NewSites) {
    PrintSiteData $site.name $site.prefix $offset -IsNew
  }
  PrintHeaderLine $configData.MainMenuTitle
  $NoSiteData = $false
}

if($NoSiteData)
{
  Write-Host ""
  Write-Host "No Site Data Exists  :("
}

Write-Host ""
Write-Host "1) Add New Site  -  2) Commit New Sites  -  3) Clear New Sites  -  4) Back to main menu  -  " -nonewline
Write-Host "5) Remove Site" -Foregroundcolor Red
$result = Get-UserSelection $options $ScriptFileName

return $result
