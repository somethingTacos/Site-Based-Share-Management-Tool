function Write-Log($SendingScript,$Message, $logType)
{
  $date = Get-Date -format "MM-dd-yy"

  $logFile = "./Logs/$logType/$($logType)_$date.log"

  $timestamp = Get-Date -format "MM/dd/yy - hh:mm:ss tt"

  $LogMessage = "[ $timestamp ][ $SendingScript ]: $Message"

  $LogMessage | Out-File $logFile -append -Encoding utf8
}
