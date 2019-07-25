Import-Module -Name "./Modules/MenuPrinter.psm1"
Import-Module -Name "./Modules/logging.psm1"
Import-Module -Name "./Modules/ShareData.psm1"
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | Select -index 0
$configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"


$operation = ""
do
{
  $operation = &"./Scripts/Screens/PrintDepartmentFolderMenu"

  if($operation -ne "Invalid")
  {
    if($operation -ne "Back to main menu")
    {
      Write-Log "$ScriptFileName" "Starting operation - $operation" "Program"
      switch($operation)
      {
        "Add New Department Folder" { Read-FolderData $ScriptFileName }
        "Commit New Department Folders" {
          if((Test-Path("./Data/NewFolders.csv")))
          {
            &"./Scripts/ShareHelpers/AddNewDepartmentFolder"
          }
          else
          {
            Write-Host ""
            Write-Host "No new folders to commit"
            PressEnterToContinue
          }
        }
        "Clear New Folders" { Remove-NonCommitedData $ScriptFileName -FolderData }
        "add umfs" { Add-UnmanagedFolders }
        "remove mfs" { Remove-MissingDeptFolders }
      }
    }
  }
  else
  {
    PressEnterToContinue
  }
}
until($operation -eq "Back to main menu")
