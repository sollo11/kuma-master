# Copyright � 2008, Microsoft Corporation. All rights reserved.

trap { break }

#
# The Printer diangosis global trouble shooter, we can control trouble shooter the flow here.
#
. .\CL_Utility.ps1

#
# Check the status of the spooler service.
#
if((RunDiagnosticScript .\TS_SpoolerService.ps1) -eq $false)
{
    return
}

#
# Spooler service is functioning incorrectly
#
.\TS_SpoolerCrashing.ps1

[bool]$needCheckNoPrinterInstalled = $true

#
# Get name of non-virtual printer selected
#
[string]$printerName = ""

$printers = Get-WmiObject Win32_Printer

if($printers -ne $null)
{

    #
    # Create hash of all printers
    #
	$htAllPrinter = @{}

    #
    # Create hash of non-virtual printers
    #
    $htPrinter = @{}

    foreach($printer in $printers)
    {

         $htAllPrinter.Add($printer.Name, $printer)

         if(-not (IsVirtualPrinter $printer.DeviceID))
         {
             $htPrinter.Add($printer.Name, $printer)
         }
    }

    #
    # Build programmatic list of all printers.
    #
    $choices = New-Object System.Collections.ArrayList
    foreach($item in $htAllPrinter.keys)
    {
        $name = $htAllPrinter[$item].Name
        $description = $htAllPrinter[$item].Description
        $value = $htAllPrinter[$item].Name
        $choices += @{"Name" = "$name"; "Description" = "$description"; "Value" = "$value"}
    }

    #
    # Check if a printer to diagnose has been programmatically specified by an application
    # or metapackage (like DeviceCenter).
    #
    try {
         $printerName = Get-DiagInput -id IT_AutoSelectPrinter -choice $choices
         $needCheckNoPrinterInstalled = $false
    } catch {

        #
        # If this question isn't answered, ask the user which printer to run from a filtered list
        #

	    if($htPrinter.Count -eq 1)
	    {
	        $needCheckNoPrinterInstalled = $false
                foreach($item in $htPrinter.keys)
	        {
	            $printerName = $htPrinter[$item].Name
	        }
	    }
	    elseif($htPrinter.Count -gt 1)
	    {
                $needCheckNoPrinterInstalled = $false

                #
	        # Ask the user which printer should be the default printer.
	        #
	        $choices = New-Object System.Collections.ArrayList
	        foreach($item in $htPrinter.keys)
	        {
	            $name = $htPrinter[$item].Name
	            $description = $htPrinter[$item].Description
	            $value = $htPrinter[$item].Name
	            $choices += @{"Name" = "$name"; "Description" = "$description"; "Value" = "$value"}
	        }
	        $printerName = Get-DiagInput  -id "IT_SelectPrinter" -choice $choices
	        if($printerName -eq "RESCAN")
	        {
	            $printerName = ""
	            Update-DiagRootCause -id "RC_NoPrinterInstalled" -Detected $true -parameter @{ "DEVICEID" = "ScanOnly"; "PRINTERCOUNT"=$htPrinter.Count}
	            return
	        }
	    }
	}
}

#
# Check no non-virtual printer
#
if($needCheckNoPrinterInstalled)
{
    .\TS_NoPrinterInstalled.ps1
}

if(-not [string]::IsNullorEmpty($printerName))
{
    #
    # Check the default printer
    #
    .\TS_DefaultPrinter.ps1 $printerName
    #
    # Check the printer driver
    #
    .\TS_PrinterDriver.ps1 $printerName

    #
    # Check the default printer's connection.
    #
    .\TS_CannotConnect.ps1 $printerName

    #
    # Check printer power off
    #
    .\TS_PrinterTurnedOff.ps1 $printerName

    #
    # Check the low toner
    #
    .\TS_OutOfToner.ps1 $printerName

    #
    # Check the low paper
    #
    .\TS_OutOfPaper.ps1 $printerName

    #
    # Check the paper jammed
    #
    .\TS_PaperJam.ps1 $printerName

    #
    # Check the current user's print jobs.
    #
    .\TS_PrintJobsStuck.ps1 $printerName

    #
    # Check whether the local printer is shared on the Homegroup
    #
    .\TS_HomeGroup.ps1 $printerName

    #
    # Check whether the printer driver has encountered an error
    #
    .\TS_PrinterDriverError.ps1 $printerName
}
