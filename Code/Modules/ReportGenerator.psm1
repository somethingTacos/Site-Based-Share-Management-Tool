function Get-CanonicalName ([string[]]$DistinguishedName) {
    foreach ($dn in $DistinguishedName) {
        $d = $dn.Split(',')
        $arr = (@(($d | Where-Object { $_ -notmatch 'DC=' }) | ForEach-Object { $_.Substring(3) }))
        [array]::Reverse($arr)

        "{0}/{1}" -f  (($d | Where-Object { $_ -match 'dc=' } | ForEach-Object { $_.Replace('DC=','') }) -join '.'), ($arr -join '/')
    }
}

function Get-AddReport
{
  param(
     $MainHeader,
     $NewSites,
     $GroupsToAdd,
     $FoldersToAdd,
     $SecurityToAdd,
    [switch] $preOp
  )

  $configData = Import-LocalizedData -BaseDirectory "./Data/" -FileName "config.psd1"
  $preContent = "<H1>$($MainHeader):</H1>"
  if($preOp)
  {
    $preContent = "<H1>Pre-Operation $($MainHeader):</H1>"
  }

  $preContent += "<H2>"
  $NewSites | ForEach-Object {
    $siteInfo = $_.Name + " : " + $_.Prefix
    $preContent += $siteInfo
    $preContent += "<br>"
  }

  $gCount = ($GroupsToAdd | measure | select Count -ExpandProperty Count)
  $fCount = ($FoldersToAdd | measure | select Count -ExpandProperty Count)
  $sCount = ($SecurityToAdd | measure | select Count -ExpandProperty Count)

  $preContent += "</H2>"
  $preContent += "<H3><pre>"
  $totalOps = $gCount + $fCount + $sCount
  if($preOp)
  {
    $H3 += "Groups To Add: $($gCount)        "
    $H3 += "Folders To Add: $($fCount)        "
    $H3 += "Security To Add: $($sCount)        "
    $H3 += "Total Operations: $totalOps"
  }
  else
  {
    $groupErrors = 0

    if($gCount -ne $null -and $gCount -ne 0)
    {
      $GroupsToAdd | Foreach-Object {
        if($_.Status -ne "Complete") {$groupErrors += 1}
      }
    }
    $folderErrors = 0
    if($fCount -ne $null -and $fCount -ne 0)
    {
      $FoldersToAdd | Foreach-Object {
        if($_.Status -ne "Complete") {$folderErrors += 1}
      }
    }
    $securityErrors = 0
    if($sCount -ne $null -and $sCount -ne 0)
    {
      $SecurityToAdd | Foreach-Object {
        if($_.Status -ne "Complete") {$securityErrors += 1}
      }
    }

    $groupsCompleted = $gCount - $groupErrors
    $foldersCompleted = $fCount - $folderErrors
    $securityCompleted = $sCount - $securityErrors
    $totalCompleted = $groupsCompleted + $foldersCompleted + $securityCompleted
    $totalErrors = $groupErrors + $folderErrors + $securityErrors

    $H3 += "Groups Added: $($groupsCompleted)        "
    $H3 += "Folders Added: $($foldersCompleted)        "
    $H3 += "Security Added: $($securityCompleted)        "
    $H3 += "Successful Operations: $totalCompleted        "
    $H3 += "Errors: $totalErrors"
  }

  $preContent += $H3
  $preContent += "</pre></H3>"

  $AddSiteReport = @()

  if($gCount -ne $null -and $gCount -ne 0)
  {
    $GroupsToAdd | Foreach-Object {
      $cn = Get-CanonicalName $_.GroupOU
      $newRowData = New-Object psobject
      $newRowData | Add-Member -Type NoteProperty -Name "Operation" -Value "Add AD Group"
      $newRowData | Add-Member -Type NoteProperty -Name "Object Path" -Value $cn
      $newRowData | Add-Member -Type NoteProperty -Name "Object Name" -Value $_.GroupName
      $newRowData | Add-Member -Type NoteProperty -Name "Note" -Value ""
      $newRowData | Add-Member -Type NoteProperty -Name "Status" -Value $_.Status

      $AddSiteReport += $newRowData
    }
  }

  if($fCount -ne $null -and $fCount -ne 0)
  {
    $FoldersToAdd | Foreach-Object {
      $newRowData = New-Object psobject
      $newRowData | Add-Member -Type NoteProperty -Name "Operation" -Value "Add Share Folder"
      $newRowData | Add-Member -Type NoteProperty -Name "Object Path" -Value $_.FolderPath
      $newRowData | Add-Member -Type NoteProperty -Name "Object Name" -Value $_.FolderName
      $newRowData | Add-Member -Type NoteProperty -Name "Note" -Value ""
      $newRowData | Add-Member -Type NoteProperty -Name "Status" -Value $_.Status

      $AddSiteReport += $newRowData
    }
  }

  if($sCount -ne $null -and $sCount -ne 0)
  {
    $SecurityToAdd | Foreach-Object {
      $newRowData = New-Object psobject
      $newRowData | Add-Member -Type NoteProperty -Name "Operation" -Value "Add Group Permissions"
      $newRowData | Add-Member -Type NoteProperty -Name "Object Path" -Value $_.FolderPath
      $newRowData | Add-Member -Type NoteProperty -Name "Object Name" -Value $_.GroupName
      $AdminGroup = $configData.FileServiceAdminGroup
      if($_.GroupName -eq "$AdminGroup")
      {
        $note = $_.AccessLevel + ", Inheritance check"
        $newRowData | Add-Member -Type NoteProperty -Name "Note" -Value $note
      }
      else
      {
        $newRowData | Add-Member -Type NoteProperty -Name "Note" -Value $_.AccessLevel
      }
      $newRowData | Add-Member -Type NoteProperty -Name "Status" -Value $_.Status

      $AddSiteReport += $newRowData
    }
  }

  #---------------------------------------------------

  $fragments = @()
  $fragments += $preContent
  [xml]$html = $AddSiteReport | convertto-html -Fragment

  for ($i=1;$i -le $html.table.tr.count-1;$i++) {
    if ($html.table.tr[$i].td[4] -eq "Error") {
      $class = $html.CreateAttribute("class")
      $class.value = 'error'
      $html.table.tr[$i].attributes.append($class) | out-null
    }
    elseif($html.table.tr[$i].td[4] -eq "Pending") {
      $class = $html.CreateAttribute("class")
      $class.value = 'pending'
      $html.table.tr[$i].attributes.append($class) | out-null
    }
    elseif($html.table.tr[$i].td[4] -eq "Complete") {
      $class = $html.CreateAttribute("class")
      $class.value = 'complete'
      $html.table.tr[$i].attributes.append($class) | out-null
    }
  }
  $fragments += $html.InnerXml
  $fragments += "<p class='footer'>This report was created on $(get-date)</p>"

  #---------------------------------------------------

  $covertParams = @{
# PreContent = $preContent
# PostContent = "<p class='footer'>This report was created on $(get-date)</p>"
head = @"
<style>
body { background-color:#E5E4E2;
       font-family:Monospace;
       font-size:14pt; }
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TR:nth-child(odd) {background-color: lightgray}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #135ba2; color: lightgray}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
.pending {
  color: Purple;
}
.error {
  color: Red;
}
.complete {
  color: DarkGreen;
}
.footer
{ color: #135ba2;
  margin-left:10px;
  font-family:Tahoma;
  font-size:12pt;
  font-weight: bold
}
</style>
"@
body = $fragments
  }


  if($preOp)
  {
    $date = Get-Date -format "MM-dd-yy"
    # $AddSiteReport |
    ConvertTo-HTML @covertParams | Out-File "./Reports/temp_SiteAdd_$date.html"
    Invoke-Expression "./Reports/temp_SiteAdd_$date.html"
  }
  else
  {
    $date = Get-Date -format "MM-dd-yy_hh-mm-ss-tt"
    # $AddSiteReport |
    ConvertTo-HTML @covertParams | Out-File "./Reports/SiteAdd_$date.html"
    Invoke-Expression "./Reports/SiteAdd_$date.html"
  }

}
