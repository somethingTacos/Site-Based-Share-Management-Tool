$configExist = $false
$MainMenuTitle = "" #done
$ShareFolderRootPath = "" #done
$FileServiceAdminGroup = "" #done
$GroupNamePrefix = "" #done
$ShareGroupsOU = "" #done
$IsADDC = $true #done
$RemoteADDC = "" #done
$DCPath = "" #done

$CreateNewOU = $false
$CreateNewAdminGroup = $false
$cred = ""
$cancelSetup = $false
$DomainName = $env:USERDNSDOMAIN


Import-Module -Name "./Modules/logging.psm1"
$ScriptFileName = $MyInvocation.MyCommand.Name.Split('.') | Select -index 0


Function RemoteADAction
{
  param(
    $RemoteServer,
    $creds,
    $scriptBlock,
    $splatter,
    [switch] $returnData
  )
  $SessError = $false
  $sess = New-PSSession -Credential $creds -ComputerName "$RemoteServer"
  if($sess)
  {
    Invoke-Command $sess -Scriptblock { ImportSystemModules }

    if($returnData)
    {
        $SessError = Invoke-Command -Session $sess -ArgumentList $splatter -Scriptblock $scriptBlock
    }
    else
    {
      if((Invoke-Command -Session $sess -ArgumentList $splatter -Scriptblock $scriptBlock)) #returns true if command succeeded, false if it failed
      {
        $SessError = $true
      }
    }
  }

  try
  {
    Remove-PSSession $sess
  }
  catch { $SessError = "Error" } #returns error is sessions couldn't start

  return $SessError
}


Function Get-Folder($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null

    $foldername = New-Object System.Windows.Forms.FolderBrowserDialog
    $foldername.Description = "Select a folder"
    $foldername.rootfolder = "MyComputer"

    if($foldername.ShowDialog() -eq "OK") {
        $folder += $foldername.SelectedPath
    }
    return $folder
}

Write-Warning "You may be asked to authenticate to your domain during this configuration process"
Write-host ""
Write-Host "--New Config Creation Started--" -Foregroundcolor Green

function Set-RemoteADDC
{
  Write-Host ""
  $ADDC = Read-Host("Is this computer '$env:COMPUTERNAME' an Active Directory Domain Controller (AD DC)? (Y/[N])")

  if($ADDC -ne "Y" -or $ADDC -ne "y")
  {
    Write-Host ""
    Write-Warning "Please ensure the below instructions are applicable to your environment before running any commands!!"
    Write-Host ""
    Write-Host "To enable remote powershell sessions on your AD DC, please run the following commands on both this computer"
    Write-Host " and your remote AD DC (where 'RemoteComputerName' is the hostname of the remote computer):"
    Write-Host ""
    Write-Host "Enable-PSRemoting -Force"
    Write-Host "winrm set winrm/config/client '@{TrustedHosts=""RemoteComputerName""}'"
    Write-Host "Restart-Service WinRM"
    Write-Host ""
    Write-Host "Please run those commands on both computers before continuing"
    Write-Host ""
    $script:RemoteADDC = Read-Host("Enter the remote AD DC hostname")
    $script:IsADDC = $false
  }
  else
  {
    $script:IsADDC = $true
  }

  Write-Host "'$env:COMPUTERNAME' is an AD DC: " -nonewline
  if($script:IsADDC)
  {
    Write-host "True" -Foregroundcolor Green
  }
  else
  {
    Write-Host "False" -Foregroundcolor Red
    Write-Host "Remote AD DC: " -nonewline
    Write-Host "$script:RemoteADDC" -Foregroundcolor Cyan
  }

  $confirmRemoteADDC = Read-Host("Is the info above correct for your setup? (Y/[N])")
  if($confirmRemoteADDC -eq "Y" -or $confirmRemoteADDC -eq "y")
  {
    $script:continueOp = $true
  }
}

function Set-DCPath
{
  $proceed = $false
  Write-Host ""
  Write-Host "DC logon domain: '" -nonewline
  Write-Host "$DomainName" -Foregroundcolor Cyan -nonewline
  Write-Host "'"
  $confirmDomain = Read-Host("Is this domain correct? (Y/[N])")
  if($confirmDomain -ne "Y" -or $confirmDomain -ne "y")
  {
    do
    {
      Write-Host ""
      $DomainName = Read-Host("Enter the full DC path of the logon domain")
      Write-Host "DC logon domain: '" -nonewline
      Write-Host "$DomainName" -Foregroundcolor Cyan -nonewline
      Write-Host "'"

      $confirmDomainName = Read-Host("Is this domain correct? (Y/[N])")
      if($confirmDomainName -eq "Y" -or $confirmDomainName -eq "y")
      {
        $proceed = $true
      }
    }
    until($proceed)
  }

  $DC = $DomainName.Split('.')
  $DCArray = @()
  $DC | ForEach-Object {
    $DCArray += "DC=$_"
  }
  $script:DCPath = [System.String]::Join(',', $DCArray)
  $script:continueOp = $true
}


function Set-ShareGroupsOU
{
  Write-Host ""
  Write-Host "Enter a name for the OU to store the security groups created by this utility"
  Write-Host "The OU will be created under the domain root: '$script:DomainName'"
  $script:ShareGroupsOU = Read-Host("Enter OU Name")
  $script:ShareGroupsOU = $script:ShareGroupsOU.Replace(' ','')

  if($script:ShareGroupsOU -ne "")
  {
    if($script:IsADDC)
    {
      if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""OU=$script:ShareGroupsOU,$script:DCPath""")
      {
        Write-Warning "The OU name '$script:ShareGroupsOU' is in use by another domain root OU"
        $confirmUseExistingOU = Read-Host("Are you sure you want to use this OU? (Y/[N])")

        if($confirmUseExistingOU -eq "Y" -or $confirmUseExistingOU -eq "y")
        {
          $script:continueOp = $true
        }
      }
      else
      {
        $confirmOUCreation = Read-Host("Confirm Creation of OU: '$script:ShareGroupsOU'? (Y/[N])")
        if($confirmOUCreation -eq "Y" -or $confirmOUCreation -eq "y")
        {
          Write-Host "New OU '$script:ShareGroupsOU' will be created" -Foregroundcolor Green
          $script:CreateNewOU = $true
          $script:continueOp = $true
        }
      }
    }
    else
    {
      $scriptBlock = {
        param(
          $splatter
        )

        $returnValue = $false
        try
        {
          if(Get-ADOrganizationalUnit @splatter)
          {
            $returnValue = $true
          }
        }
        catch {  } #do nothing
        return $returnValue
      }

      $splatter = @{
        Filter = "DistinguishedName -like ""OU=$script:ShareGroupsOU,$script:DCPath"""
      }

      $script:cred = Get-Credential

      switch(RemoteADAction $script:RemoteADDC $script:cred $scriptBlock $splatter)
      {
        "Error" {
          Write-Host ""
          Write-Warning "Server or authentication Error. Remote Session Could not be started!"
          Write-Warning "If the remote server name '$script:RemoteADDC' is incorrect, restart configuration setup"
        } #remote session could not start - Auth/Server Error
        $true {
          $lastOutput = "Good"
          Write-Warning "The OU name '$script:ShareGroupsOU' is in use by another domain root OU"
          $confirmUseExistingOU = Read-Host("Are you sure you want to use this OU? (Y/[N])")

          if($confirmUseExistingOU -eq "Y" -or $confirmUseExistingOU -eq "y")
          {
            $script:continueOp = $true
          }
        } #OU exists
        $false {
          $confirmOUCreation = Read-Host("Confirm Creation of OU: '$script:ShareGroupsOU'? (Y/[N])")
          if($confirmOUCreation -eq "Y" -or $confirmOUCreation -eq "y")
          {
            Write-Host "New OU '$script:ShareGroupsOU' will be created" -Foregroundcolor Green
            $script:CreateNewOU = $true
            $script:continueOp = $true
          }
        } #OU does not exist
      }
    }
  }
}

function Set-FileServiceAdminGroup
{
  Write-Host ""
  Write-Host "Enter the name of an AD Group to manage the share. This group will have fullcontrol to all share data."
  $script:FileServiceAdminGroup = Read-Host("Enter Group Name")
  if($script:FileServiceAdminGroup -ne "")
  {
    if($script:IsADDC)
    {
      ImportSystemModules
      $groupExists = $false
      try { if(Get-ADGroup $script:FileServiceAdminGroup) { $groupExists = $true }} catch { } #do nothing
      if($groupExists -eq $false)
      {
        $confirmNewGroup = Read-Host("Confirm creation of this group: '$script:FileServiceAdminGroup'? (Y/[N])")
        if($confirmNewGroup -eq "Y" -or $confirmNewGroup -eq "y")
        {
          Write-Host "New Group '$script:FileServiceAdminGroup' will be created" -Foregroundcolor Green
          $script:CreateNewAdminGroup = $true
          $script:continueOp = $true
        }
      }
      else
      {
        Write-Warning "the group '$script:FileServiceAdminGroup' already exists."
        $confirmUseExistingGroup = Read-Host("Do you want to use this group as the share admins group? (Y/[N])")
        if($confirmUseExistingGroup -eq "Y" -or $confirmUseExistingGroup -eq "y")
        {
          $script:continueOp = $true
        }
      }
    }
    else
    {
      $scriptBlock = {
        param(
          $splatter
        )

        $returnValue = $false
        try
        {
          if(Get-ADGroup @splatter)
          {
            $returnValue = $true
          }
        }
        catch {  } #do nothing
        return $returnValue
      }

      $splatter = @{
        Identity = "$script:FileServiceAdminGroup"
      }

      if(-not (RemoteADAction $script:RemoteADDC $script:cred $scriptBlock $splatter))
      {
        $confirmNewGroup = Read-Host("Confirm creation of this group: '$script:FileServiceAdminGroup'? (Y/[N])")
        if($confirmNewGroup -eq "Y" -or $confirmNewGroup -eq "y")
        {
          Write-Host "New Group '$script:FileServiceAdminGroup' will be created" -Foregroundcolor Green
          $script:CreateNewAdminGroup = $true
          $script:continueOp = $true
        }
      }
      else
      {
        Write-Warning "the group '$script:FileServiceAdminGroup' already exists."
        $confirmUseExistingGroup = Read-Host("Do you want to use this group as the share admins group? (Y/[N])")
        if($confirmUseExistingGroup -eq "Y" -or $confirmUseExistingGroup -eq "y")
        {
          $script:continueOp = $true
        }
      }
    }
  }
}

function Set-GroupNamePrefix
{
  Write-Host ""
  Write-Host "Enter a group name prefix for the group names. Just press enter to not use the prefix."
  $script:GroupNamePrefix = Read-Host("Group Name prefix")

  $script:GroupNamePrefix = $script:GroupNamePrefix.Replace(' ','')
  $script:GroupNamePrefix = $script:GroupNamePrefix -replace '[^a-zA-Z0-9]',''
  if($script:GroupNamePrefix -eq "")
  {
    $PrefixInfo = "< No Prefix >"
  }
  else
  {
    $PrefixInfo = "$script:GroupNamePrefix"
  }

  Write-Host "Prefix: " -nonewline
  Write-Host "$PrefixInfo" -Foregroundcolor Cyan
  $usePrefix = Read-Host("Use this prefix? (Y/[N])")
  if($usePrefix -eq "Y" -or $usePrefix -eq "y")
  {
    $script:continueOp = $true
  }
}

function Set-MainMenuTitle
{
  Write-Host ""
  $script:MainMenuTitle = Read-Host("Enter a Main Menu Title")
  Write-Host ""
  Write-Host "Menu Title:"
  Write-Host "$script:MainMenuTitle" -Foregroundcolor Cyan

  $confirmMainMenuTitle = Read-Host("Use this title? (Y/[N])")
  if($confirmMainMenuTitle -eq "Y" -or $confirmMainMenuTitle -eq "y")
  {
    $script:continueOp = $true
  }
}

function Set-ShareFolderRootPath
{
  Write-Host ""
  Write-Host "Choose the root share folder: " -nonewline
  Write-Host "Folder Dialog Opened!" -Foregroundcolor Green
  $script:ShareFolderRootPath = Get-Folder
  Write-host "Share folder root path:"
  Write-Host "$script:ShareFolderRootPath" -Foregroundcolor Cyan
  $confirmShareFolderRootPath = Read-host("Path is correct? (Y/[N])")

  if($confirmShareFolderRootPath -eq "Y" -or $confirmShareFolderRootPath -eq "y")
  {
    $script:continueOp = $true
  }
}

function Set-ConfigData
{
  function printPair
  {
    param(
      $Key,
      $Value
    )

    Write-Host "$Key : '" -nonewline
    Write-Host "$Value" -Foregroundcolor DarkCyan -nonewline
    Write-Host "'"
    Write-Host ""
  }

  Clear
  PrintPair "MainMenuTitle" $script:MainMenuTitle
  PrintPair "ShareFolderRootPath" $script:ShareFolderRootPath
  PrintPair "FileServiceAdminGroup" $script:FileServiceAdminGroup
  PrintPair "ShareGroupsOU" $script:ShareGroupsOU
  PrintPair "IsADDC" $script:IsADDC
  PrintPair "RemoteADDC" $script:RemoteADDC
  PrintPair "GroupNamePrefix" $script:GroupNamePrefix
  PrintPair "DCPath" $script:DCPath

  $installNTFSSecurityModule = (!(Test-Path("C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules\NTFSSecurity")))
  if($CreateNewOU) { Write-Host "The OU '$script:ShareGroupsOU' will be created" -Foregroundcolor DarkCyan }
  if($CreateNewAdminGroup) { Write-Host "The group '$script:FileServiceAdminGroup' will be created" -Foregroundcolor DarkCyan }
  if($installNTFSSecurityModule) { Write-Host "NTFSSecurity Powershell Module will be installed" -Foregroundcolor DarkCyan }

  Write-host ""
  $confirmConfig = Read-Host("Is all the information above correct? (Y/[N])")

  if($confirmConfig -eq "Y" -or $confirmConfig -eq "y")
  {
    $abortSetup = $false

    if($script:IsADDC)
    {
      if($CreateNewOU)
      {
        New-ADOrganizationalUnit -Name "$script:ShareGroupsOU"
        if(-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""OU=$script:ShareGroupsOU,$script:DCPath"""))
        {
          Write-Warning "Something went wrong, counld not create '$script:ShareGroupsOU' OU. Aborting Operation!"
          $abortSetup = $true
        }
      }
      if($CreateNewAdminGroup -and -not $abortSetup)
      {
        $splatter = @{
          Name = "$script:FileServiceAdminGroup"
          GroupCategory = 'Security'
          GroupScope = 'Global'
          SamAccountName = "$script:FileServiceAdminGroup"
          Description = "A group to manage the company file share"
          Path = "OU=$script:ShareGroupsOU,$script:DCPath"
        }

        New-ADGroup @splatter
        if(-not (Get-ADGroup -Filter "Name -like ""$script:FileServiceAdminGroup"""))
        {
          Write-Warning "Something went wrong, counld not create '$script:FileServiceAdminGroup' group. Aborting Operation!"
          $abortSetup = $true
        }
      }
    }
  else
  {
    if($CreateNewOU)
    {
      $scriptBlock = {
        param(
          $splatter
        )

        $returnValue = $false
        try
        {
          $OUName = $splatter.Name
          $OUPath = $splatter.Path
          New-ADOrganizationalUnit -Name $OUName
          if(Get-ADOrganizationalUnit -Filter "DistinguishedName -like ""$OUPath""")
          {
            $returnValue = $true
          }
        }
        catch {  } #do nothing
        return $returnValue
      }

      $splatter = @{
        Name = "$script:ShareGroupsOU"
        Path = "OU=$script:ShareGroupsOU,$script:DCPath"
      }

      $OUCreateSucceeded = RemoteADAction $script:RemoteADDC $script:cred $scriptBlock $splatter
      if(-not $OUCreateSucceeded)
      {
        Write-Warning "Something went wrong, counld not create '$script:ShareGroupsOU' OU. Aborting Operation!"
        $abortSetup = $true
      }
    }
    if($CreateNewAdminGroup -and -not $abortSetup)
    {
      $scriptBlock = {
        param(
          $splatter
        )

        $returnValue = $false
        try
        {
          New-ADGroup @splatter
          $groupName = $splatter.Name
          if(Get-ADGroup -Filter "Name -like ""$groupName""")
          {
            $returnValue = $true
          }
        }
        catch {  } #do nothing
        return $returnValue
      }

      $splatter = @{
        Name = "$script:FileServiceAdminGroup"
        GroupCategory = 'Security'
        GroupScope = 'Global'
        SamAccountName = $script:FileServiceAdminGroup
        Description = "A group to manage the company file share"
        Path = "OU=$script:ShareGroupsOU,$script:DCPath"
      }

      $AdminGroupCreateSucceeded = RemoteADAction $script:RemoteADDC $script:cred $scriptBlock $splatter
      if(-not $AdminGroupCreateSucceeded)
      {
        Write-Warning "Something went wrong, counld not create '$script:FileServiceAdminGroup' group. Aborting Operation!"
        $abortSetup = $true
      }
    }
  }
}
else
{
  $abortSetup = $true
}

if((-not $abortSetup -and $installNTFSSecurityModule))
{
  Copy-Item './Modules/NTFSSecurity/' -Destination 'C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules\NTFSSecurity' -Recurse
}

  if(!($abortSetup))
  {
    Import-Module -Name "./Modules/ShareManagement.psm1"
    Import-Module -Name "./Modules/MenuPrinter.psm1"

    PrintWaitTimer 5 "Allowing AD to update group info"
    
    AddPermissions $script:ShareFolderRootPath $script:FileServiceAdminGroup "fullcontrol"

    [int]$IsADDCint = $script:IsADDC
      Write-Log "$script:ScriptFileName" "Saving Config..." "Program"
  @"
@{
  MainMenuTitle = '$script:MainMenuTitle'
  ShareFolderRootPath = '$script:ShareFolderRootPath'
  FileServiceAdminGroup = '$script:FileServiceAdminGroup'
  ShareGroupsOU = '$script:ShareGroupsOU'
  IsADDC = '$IsADDCint'
  RemoteADDC = '$script:RemoteADDC'
  GroupNamePrefix = '$script:GroupNamePrefix'
  DCPath = '$script:DCPath'
}
"@ | Set-Content "./Data/config.psd1"

  }
}


#start calling stuff
$continueOp = $false
do { Set-RemoteADDC } until($continueOp)

$continueOp = $false
do { Set-DCPath } until($continueOp)

$continueOp = $false
do { Set-ShareGroupsOU } until($continueOp)

if(-not $cancelSetup)
{
  $continueOp = $false
  do { Set-FileServiceAdminGroup } until($continueOp)
}

if(-not $cancelSetup)
{
  $continueOp = $false
  do { Set-GroupNamePrefix } until($continueOp)
}

if(-not $cancelSetup)
{
  $continueOp = $false
  do { Set-MainMenuTitle } until($continueOp)
}

if(-not $cancelSetup)
{
  $continueOp = $false
  do { Set-ShareFolderRootPath } until($continueOp)
}

if(-not $cancelSetup)
{
  Set-ConfigData
}

if((Test-Path("./Data/config.psd1")) -eq $true)
{
  Write-Log "$ScriptFileName" "Config Saved" "Program"
  Write-Log "$ScriptFileName" "New Config Data: MainMenuTitle='$MainMenuTitle'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: ShareFolderRootPath='$ShareFolderRootPath'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: FileServiceAdminGroup='$FileServiceAdminGroup'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: GroupNamePrefix='$GroupNamePrefix'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: ShareGroupsOU='$ShareGroupsOU'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: RemoteADDC='$RemoteADDC'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: IsADDC='$IsADDC'" "Program"
  Write-Log "$ScriptFileName" "New Config Data: DCPath='$DCPath'" "Program"
  $configExist = $true

  Clear
  Write-Host "-- Config Setup Complete --" -Foregroundcolor Green
  Write-Host ""
  Write-Warning "In order for this tool to work correctly, you need to add members to '$FileServiceAdminGroup'."
  Write-Warning "I recommend making your Domain Administrator a member, if your situation allows for it."
  Write-Warning "You will need to re-log to gain your new permissions. I highly recommend you do this before proceeding."
  Write-Host ""
  Read-Host("Press Enter to continue when you are done reading the warnings.")
}
else
{
  Write-Host ""
  Write-Host "Something went wrong, config did not save  :(" -Foregroundcolor Red
}

return $configExist
