Clear
#check config exists
Import-Module -Name "./Modules/logging.psm1"
$createConfig = ""
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | select -index 0

Write-Log "$ScriptFileName" "............................START.NEW............................" "Program"


Write-Log "$ScriptFileName" "Starting Program - $(Get-Date -format g)" "Program"

if(!(Test-Path("./Data/config.psd1")))
{
  Write-Log "$ScriptFileName" "No config found - Starting config creation" "Program"
  $createConfig = &"./Scripts/Program/SetupConfig"
}
else
{
  Write-Log "$ScriptFileName" "Configuration file exists" "Program"
}

if(!(Test-Path("./Data/config.psd1")))
{
  Write-Log "$ScriptFileName" "No config found or created - Exiting" "Program"
  Write-Host ""
  Write-Host "No config found or created." -Foregroundcolor Red
}
else
{
  Write-Log "$ScriptFileName" "Starting MainMenu" "Program"
  $operation = ""
  do
  {
    $operation = ""
    $operation = &"./Scripts/Screens/PrintMainMenu"

    if($operation -ne "Invalid")
    {
      if($operation -ne "Exit Program")
      {
        Write-Log "$ScriptFileName" "Starting operation - $operation" "Program"
        #perform operation ----------------<<<----------------------------<<<
        switch($operation)
        {
          "Show Sites" { &"./Scripts/Program/ShowSites" }
          "Show Department Level Folders" { &"./Scripts/Program/ShowDepartmentFolders" }
          "Check Share Integrity" { &"./Scripts/ShareHelpers/CheckShareIntegrity" }
        }
      }
    }
    else
    {
      PressEnterToContinue
    }
  }
  until($operation -eq "Exit Program")
}

Write-Log "$ScriptFileName" "Program exiting" "Program"
Write-Host "Press " -nonewline
Write-Host "Enter " -Foregroundcolor Cyan -nonewline
Write-host "to close window" -nonewline
Read-Host("...")
