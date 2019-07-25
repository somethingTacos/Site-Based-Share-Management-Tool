Import-Module -Name "./Modules/MenuPrinter.psm1"
$configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
$options = "Show Sites", "Show Department Level Folders", "Check Share Integrity", "Exit Program"
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | Select -index 0
#start printing menu
Clear
PrintMenuHeader $configData.MainMenuTitle $configData.ShareFolderRootPath
PrintOptions $options
PrintHeaderLine $configData.MainMenuTitle

$result = Get-UserSelection $options $ScriptFileName
return $result
