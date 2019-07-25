function PrintHeaderLine($Header)
{
  for($i=0; $i -lt $Header.Length + 12; $i++)
  {
    Write-Host "=" -nonewline
  }
  Write-Host ""
}

function PrintWaitTimer($SecondsToWait, $Message)
{
  Write-Host ""
  $CounterPos = $host.UI.RawUI.CursorPosition

  for($i = $SecondsToWait; $i -gt 0; $i--)
  {
    $host.UI.RawUI.CursorPosition = $CounterPos
    Write-Host "Please wait... $($i)s : $Message  "
    [System.Threading.Thread]::Sleep(1000)
  }
}

function PrintOptions($options)
{
  for($i=0; $i -lt $options.Count; $i++)
  {
    $optionNum = $i+1
    $option = $options[$i]
    Write-Host "$optionNum) $option"
  }
}

function PrintMenuHeader($Header, $ShareFolderRootPath)
{
  Write-Host "Share Path: " -nonewline
  Write-Host "$ShareFolderRootPath" -Foregroundcolor DarkCyan

  PrintHeaderLine $Header

  for($i=0; $i -lt 6; $i++) #$Header.Length; $i++)
  {
    Write-Host " " -nonewline
  }

  Write-Host $Header
  PrintHeaderLine $Header
}

function Get-PrintOffset($data)
{
  $largestName = ""
  foreach($info in $data) {
    if($info.name.length -gt $largestName.length)
    {
      $largestName = $info.name
    }
  }

  return $largestName.Length + 3
}

function PrintSiteData
{
  param(
    $SiteName,
    $SitePrefix,
    [int]$PrintOffset,
    [switch]$IsNew
  )
  $dataColor = "DarkCyan"
  if($IsNew) { $dataColor = "Yellow" }

  Write-Host "Site Name: " -nonewline
  Write-Host "$SiteName" -Foregroundcolor $dataColor -nonewline
  $ActualOffset = $PrintOffset - $SiteName.length
  for($i=0; $i -lt $ActualOffset; $i++)
  {
    Write-Host " " -nonewline
  }
  Write-Host "Site Prefix: " -nonewline
  Write-Host "$SitePrefix" -Foregroundcolor $dataColor
}

function PrintFolderData
{
  param(
    $FolderName,
    [int]$HasGeneral,
    [int]$PrintOffset,
    [switch] $IsNew,
    [switch] $IsMissing
  )
  $dataColor = "DarkGray"
  if([bool]$HasGeneral) { $dataColor = "DarkCyan"}
  if($IsNew) { $dataColor = "Yellow" }
  $ActualOffset = 0

  if($IsMissing)
  {
    $ActualOffset = $PrintOffset - $FolderName.length - 2

    Write-Host "! FolderName: " -nonewline -Foregroundcolor White -Backgroundcolor red
    Write-Host "$FolderName" -nonewline -Foregroundcolor black -Backgroundcolor red
  }
  else
  {
    $ActualOffset = $PrintOffset - $FolderName.length
    Write-Host "FolderName: " -nonewline
    Write-Host "$FolderName" -Foregroundcolor $dataColor -nonewline
  }

  for($i=0; $i -lt $ActualOffset; $i++)
  {
    Write-Host " " -nonewline
  }

  if($IsMissing)
  {
    Write-Host "Has General: " -nonewline -Foregroundcolor White -Backgroundcolor red
    Write-Host "$([bool]$HasGeneral)" -Foregroundcolor black -Backgroundcolor red
  }
  else
  {
    Write-Host "Has General: " -nonewline
    Write-Host "$([bool]$HasGeneral)" -Foregroundcolor $dataColor
  }

}

function PressEnterToContinue
{
  Write-Host ""
  Write-Host "Press " -nonewline
  Write-Host "Enter " -Foregroundcolor Green -nonewline
  Write-host "to continue" -nonewline
  Read-Host("...")
}

function Get-UserSelection
{
  param(
    $options,
    $SendingScript,
    [switch] $allow_umfs, #allows the use of the 'add umfs' command to add unmanaged folders
    [switch] $allow_rmfs #allows the use of the 'add umfs' command to add unmanaged folders

  )

  $result = ""
  $selection = Read-Host("Enter a number to choose an option")
  try
  {
    $inputNum = [int]$selection
  }
  catch { }

  if($allow_umfs -and $selection -eq "add umfs")
  {
    return "add umfs"
  }

  if($allow_rmfs -and $selection -eq "remove missing folders")
  {
    return "remove mfs"
  }

  if($inputNum -ne $Null -and $inputNum -is [int] -and $inputNum -ne "0" -and $inputNum -lt $options.Count+1)
  {
    $selectedOption = $options[$inputNum-1]
    $result = $selectedOption
  }
  else
  {
    Write-Log "$SendingScript" "Invalid Selection - '$selection'" "Program"
    Write-Host "Please enter a valid selection: '" -nonewline
    Write-Host "$selection" -Foregroundcolor Red -nonewline
    Write-Host "' is Invalid"
    $result = "Invalid"
  }

  return $result
}

function Write-Tagged($tagType,$Message)
{
  Write-Host "[  " -nonewline
  $tagColor = "Gray"
  $CursorPos = $host.UI.RawUI.CursorPosition

  switch($tagType)
  {
    ".." { $tagColor = "Magenta" }
    {$_ -in "OK","Created","Removed"} { $tagColor = "Green" }
    {$_ -in "Exists","NonExistent"} { $tagColor = "Yellow"}
    "ERROR" { $tagColor = "Red" }
  }

  Write-Host "$tagType" -nonewline -Foregroundcolor $tagColor

  if($tagType -eq "..")
  {
    Write-Host "  ] $Message" -nonewline
    $CursorPos.X = 0
    $host.UI.RawUI.CursorPosition = $CursorPos
  }
  else
  {
    Write-Host "  ] $Message"
  }
}

#NOTE - test function for getting buffer info to make better menu layouts
# function test {
# clear
# $cursorPos = $host.UI.RawUI.CursorPosition
# $cursorPos.Y = 0
#
# for($i=0; $i -lt 10; $i++)
# {
# $width = $host.UI.RawUI.WindowSize.Width
# $cursorPos.X = $width / 2
# $host.UI.RawUI.CursorPosition = $cursorPos
# Write-Host "|"
# $cursorPos.Y += 1
# }
# }
