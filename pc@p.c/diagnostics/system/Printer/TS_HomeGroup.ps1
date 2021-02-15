# Copyright © 2008, Microsoft Corporation. All rights reserved.


PARAM($printerName)
#
# Check whether the local printer is shared on the Homegroup
#
Import-LocalizedData -BindingVariable localizationString -FileName CL_LocalizationData
Write-DiagProgress -activity $localizationString.progress_ts_homeGroup

. .\CL_Utility.ps1

function Get-HomeGroupName()
{
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\HomeGroupProvider\ServiceData"
    $item = "PeerGroupName"

    return (Get-ItemProperty -Path $path -Name $item).$item
}

function Test-HomeGroupName()
{
    return [bool](Get-HomeGroupName)
}

[bool]$result = $false

if(Test-HomeGroupName)
{
    $printerSelected = GetPrinterFromPrinterName $printerName
    if(-not $printerSelected.NetWork -and -not (PrinterIsShared $printerName))
    {
        $result = $true
    }
}

if($result)
{
    Update-DiagRootCause -id "RC_HomeGroup" -Detected $true -parameter @{ "PRINTERNAME" = $printerName}
}
else
{
    Update-DiagRootCause -id "RC_HomeGroup" -Detected $false -parameter @{ "PRINTERNAME" = $printerName}
}
