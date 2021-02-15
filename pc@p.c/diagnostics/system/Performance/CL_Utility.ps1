# Copyright © 2008, Microsoft Corporation. All rights reserved.


Import-LocalizedData -BindingVariable localizationString -FileName CL_LocalizationData

#
# Get system path of a file by adding the system path of current directory in the head of the specified file
#
function GetSystemPath([string]$fileName)
{
    if([string]::IsNullorEmpty($fileName))
    {
        WriteFunctionExceptionReport "GetSystemPath" $localizationString.throw_invalidFileName
        return
    }

    [string]$systemPath = [System.Environment]::SystemDirectory
    return Join-Path $systemPath $fileName
}

#
# Get all users info that logs on the current machine. Users info includes userName, domainName and sessionID.
#
function GetLogonUsersInfo()
{
$wtsDefinition = @"
    [DllImport("Wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WTSQuerySessionInformation(IntPtr hServer, int sessionId, int wtsInfoClass, [MarshalAs(UnmanagedType.LPWStr)] ref string ppBuffer, ref int pBytesReturned);

    [DllImport("Wtsapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WTSEnumerateSessions(IntPtr hServer, int Reserved, int Version, ref long ppSessionInfo, ref int pCount);

    [StructLayout(LayoutKind.Sequential)]
    public struct WTS_SESSION_INFO
    {
        public int SessionID;
        [MarshalAs(UnmanagedType.LPStr)]
        public String pWinStationName;
        public int State;
    }

    [DllImport("Wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr pMemory);
"@

    $wtsType = Add-Type -MemberDefinition $wtsDefinition -Name "wtsType" -UsingNamespace "System.Reflection","System.Diagnostics" -PassThru

    [int]$WTS_USER_NAME = 5
    [int]$WTS_DOMAIN_NAME = 7
    [string]$SESSOIN_ID = "sessionID"
    [string]$USER_NAME = "userName"

    [long]$lpBuffer = 0
    [int]$count = 0

    $SessionInfo = New-Object $wtsType[1]

    $userList = New-Object System.Collections.ArrayList

    [string]$functionName = "GetLogonUsersInfo"

    [bool]$retVal = $wtsType[0]::WTSEnumerateSessions([IntPtr]::Zero, 0, 1, [REF]$lpBuffer, [REF]$count)
    [int]$errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if($retVal)
    {
        [long]$p = $lpBuffer
        try
        {
            for([int]$i = 0; $i -lt $count; $i++)
            {
                $SessionInfo = [System.Runtime.InteropServices.Marshal]::PtrToStructure($p, $SessionInfo.GetType())
                $p += [System.Runtime.InteropServices.Marshal]::SizeOf($SessionInfo.GetType())
                if ($SessionInfo.SessionID -ne 0)
                {
                    [int]$pCount = 0
                    [IntPtr]$buffer = [IntPtr]::Zero
                    [string]$userName = ""
                    [string]$domainName = ""
                    [bool]$bsuccess = $wtsType[0]::WTSQuerySessionInformation([IntPtr]::Zero, $SessionInfo.SessionID, $WTS_USER_NAME, [REF]$userName, [REF]$pCount);
                    $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    if ($bsuccess)
                    {
                        if (-not [System.String]::IsNullOrEmpty($userName))
                        {
                            $bsuccess = $wtsType[0]::WTSQuerySessionInformation([IntPtr]::Zero, $SessionInfo.SessionID, $WTS_DOMAIN_NAME, [REF]$domainName, [REF]$pCount);
                            $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                            if($bsuccess)
                            {
                                $userName = $domainName + "\" + $userName
                                $userList += @{"$SESSOIN_ID" = $SessionInfo.SessionID; "$USER_NAME" = "$userName" }
                            }
                            else
                            {
                                $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                                WriteFunctionAPIExceptionReport $functionName "WTSQuerySessionInformation" $errorCode
                                return
                            }
                        }
                    }
                    else
                    {
                        WriteFunctionAPIExceptionReport $functionName "WTSQuerySessionInformation" $errorCode
                        return
                    }
                }
            }
        }
        finally
        {
            $wtsType[0]::WTSFreeMemory($lpBuffer);
        }
    }
    else
    {
        WriteFunctionAPIExceptionReport $functionName "WTSEnumerateSessions" $errorCode
        return
    }
    return $userList
}

#
# Get the the Add-Type of Window API.
#
function GetWindowType()
{
$windowDefinition = @"
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, [MarshalAs(UnmanagedType.LPWStr)] string lpszClass, [MarshalAs(UnmanagedType.LPWStr)] string lpszWindow);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetWindowPos(IntPtr hWnd, int hWndInsertAfter, int X, int Y, int cx, int cy, int uFlags);
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int SendMessage(IntPtr hwnd, int wMsg, int wParam, int lParam);

"@

    $windowType = Add-Type -MemberDefinition $windowDefinition -Name "windowType" -UsingNamespace "System.Reflection","System.Diagnostics" -PassThru
    return $windowType
}

#
# Write function exception to debug report
#
function WriteFunctionExceptionReport([string]$functionName, [string]$exceptionInfo)
{
    [string]$errorFunctionName = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.error_function_name, $functionName)
    [string]$errorFunctionDescription = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.error_function_description, $functionName)
    $exceptionInfo | select-object -Property @{Name=$localizationString.error_information; Expression={$_}} | convertto-xml | Update-DiagReport -id $functionName -name $errorFunctionName -description $errorFunctionDescription -verbosity Debug
}

#
# Write API exception in function to debug report
#
function WriteFunctionAPIExceptionReport([string]$functionName, [string]$APIName, [int]$errorCode)
{
    [string]$exceptionInfo = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.throw_win32APIFailed, $APIName, $errorCode)
    WriteFunctionExceptionReport $functionName $exceptionInfo
}

#
# Write API exception in file to debug report
#
function WriteFileAPIExceptionReport([string]$fileName, [string]$APIName, [int]$errorCode)
{
    [string]$errorFileName = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.error_file_name, $fileName)
    [string]$errorFileDescription = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.error_file_description, $fileName)
    [string]$exceptionInfo = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.throw_win32APIFailed, $APIName, $errorCode)
    $exceptionInfo | select-object -Property @{Name=$localizationString.error_information; Expression={$_}} | convertto-xml | Update-DiagReport -id $fileName -name $errorFileName -description $errorFileDescription -verbosity Debug
}

#
# Write function exception to debug report
#
function WriteFileExceptionReport([string]$fileName, [string]$exceptionInfo)
{
    [string]$errorFileName = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.error_file_name, $fileName)
    [string]$errorFileDescription = [System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, $localizationString.error_file_description, $fileName)
    $exceptionInfo | select-object -Property @{Name=$localizationString.error_information; Expression={$_}} | convertto-xml | Update-DiagReport -id $fileName -name $errorFileName -description $errorFileDescription -verbosity Debug
}

#
# Create registry key
#
function CreateRegistryKey([string]$msKey)
{
    if((Test-path($msKey)))
    {
        return
    }
    $index = $mskey.LastIndexOf("\")
    $oldKey = $msKey.Substring(0, $index)
    $newKey = $msKey.Substring($index+1)
    if(-not (Test-path($oldKey)))
    {
        CreateRegistryKey $oldKey
    }
    New-Item -Path $oldkey -Name $newKey
}

#
# Backup the startup programe registry key to "HKLM:\Software\Microsoft\Shared Tools\MSConfig\startupreg"
#
function BackupStartupRegistryKey([string]$key, [string]$keyValue)
{
    [string]$functionName = "BackupStartupRegistryKey"
    if([string]::IsNullorEmpty($key))
    {
        WriteFunctionExceptionReport $functionName $localizationString.throw_invalidKey
        return
    }
    if([string]::IsNullorEmpty($keyValue))
    {
        WriteFunctionExceptionReport $functionName $localizationString.throw_invalidKeyValue
        return
    }
    [string]$data = (Get-ItemProperty -Path $key -Name $keyValue).$keyValue

    $mskey = "HKLM:\Software\Microsoft\Shared Tools\MSConfig\startupreg"
    CreateRegistryKey $mskey
    [string]$newKeyPath = "$msKey\$keyValue"
    if(-not (Test-Path($newKeyPath)))
    {
        $newKey = New-Item -Path $msKey -Name $keyValue
        $date = [System.DateTime]::Now
        New-ItemProperty -Path $newKeyPath -Name "command" -PropertyType String -Value "$data" > $null
        New-ItemProperty -Path $newKeyPath -Name "hkey" -PropertyType String -Value $key.SubString(0, 4) > $null
        New-ItemProperty -Path $newKeyPath -Name "inimapping" -PropertyType String -Value "0" > $null
        New-ItemProperty -Path $newKeyPath -Name "item" -PropertyType String -Value "$keyValue" > $null
        New-ItemProperty -Path $newKeyPath -Name "key" -PropertyType String -Value $key.SubString(6) > $null
        New-ItemProperty -Path $newKeyPath -Name "DAY" -PropertyType DWORD -Value $date.Day > $null
        New-ItemProperty -Path $newKeyPath -Name "HOUR" -PropertyType DWORD -Value $date.Hour > $null
        New-ItemProperty -Path $newKeyPath -Name "MINUTE" -PropertyType DWORD -Value $date.Minute > $null
        New-ItemProperty -Path $newKeyPath -Name "SECOND" -PropertyType DWORD -Value $date.Second > $null
        New-ItemProperty -Path $newKeyPath -Name "MONTH" -PropertyType DWORD -Value $date.Month > $null
        New-ItemProperty -Path $newKeyPath -Name "YEAR" -PropertyType DWORD -Value $date.Year > $null
    }
}

#
# Backup the startup link file to "HKLM:\Software\Microsoft\Shared Tools\MSConfig\startupreg"
#
function BackupStartupLinkFile([System.IO.FileInfo]$file)
{
    [string]$functionName = "BackupStartupLinkFile"
    if($file -eq $null)
    {
        WriteFunctionExceptionReport $functionName $localizationString.throw_invalidFile
        return
    }
    [string]$backupPath = "$env:windir\pss"
    [string]$programData = "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    [string]$commonStartup = ".CommonStartup"
    [string]$startup = ".Startup"
    [string]$backupExtension = ""
    if(-not(Test-Path($backupPath)))
    {
        New-Item -Path $backupPath -ItemType "directory" > $null
    }
    if( $file.DirectoryName -eq $programData)
    {
        $backupExtension = $commonStartup
    }
    else
    {
        $backupExtension = $startup
    }
    #
    # backup file
    #
    [string]$desFileName = $file.Name + $backupExtension
    Copy-Item -LiteralPath $file.FullName -Destination "$backupPath\$desFileName"
    #
    # backup registry key
    #
    $mskey = "HKLM:\Software\Microsoft\Shared Tools\MSConfig\startupfolder"
    CreateRegistryKey $mskey
    [string]$newKeyStr = $file.FullName.Replace("\", "^")
    [string]$newKeyPath = "$msKey\$newKeyStr"
    if(-not (Test-Path($newKeyPath)))
    {
        $newKey = New-Item -Path $msKey -Name $newKeyStr
        $date = [System.DateTime]::Now
        $shell =  New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($file.FullName)
        [string]$targetName = $shortcut.TargetPath
        New-ItemProperty -Path $newKeyPath -Name "backup" -PropertyType String -Value "$backupPath\$desFileName" > $null
        New-ItemProperty -Path $newKeyPath -Name "backupExtension" -PropertyType String -Value $backupExtension > $null
        New-ItemProperty -Path $newKeyPath -Name "command" -PropertyType String -Value $targetName > $null
        New-ItemProperty -Path $newKeyPath -Name "item" -PropertyType String -Value $file.BaseName > $null
        New-ItemProperty -Path $newKeyPath -Name "location" -PropertyType String -Value  $file.DirectoryName > $null
        New-ItemProperty -Path $newKeyPath -Name "path" -PropertyType String -Value $file.FullName > $null
        New-ItemProperty -Path $newKeyPath -Name "DAY" -PropertyType DWORD -Value $date.Day > $null
        New-ItemProperty -Path $newKeyPath -Name "HOUR" -PropertyType DWORD -Value $date.Hour > $null
        New-ItemProperty -Path $newKeyPath -Name "MINUTE" -PropertyType DWORD -Value $date.Minute > $null
        New-ItemProperty -Path $newKeyPath -Name "SECOND" -PropertyType DWORD -Value $date.Second > $null
        New-ItemProperty -Path $newKeyPath -Name "MONTH" -PropertyType DWORD -Value $date.Month > $null
        New-ItemProperty -Path $newKeyPath -Name "YEAR" -PropertyType DWORD -Value $date.Year > $null
    }
}
#
# Delete the startup programs the user selected and backup to corresponding place.
#
function RemoveStartupPrograms([string[]]$keyArray, [string[]]$linkPathArray, [string]$diagInputName, [bool]$backup=$true)
{

    $choices = New-Object -TypeName System.Collections.ArrayList
    [string]$inboxExeProductName = GetInboxExeProductName
    #
    # Perhaps the string array could be added later.
    #
    $saveValues = ,"WindowsWelcomeCenter"
    foreach($key in $keyArray)
    {
        #
        # Check whether the key is existed in registry
        #
        if(-not (Test-Path($key)))
        {
            Continue
        }
        $keyObj = Get-Item -Path $key
        #
        # Finds out the values from registry that can be removed and let user choise which values should be deleted
        #
        $names =  $keyObj.Property
        foreach($name in $names)
        {
            [bool]$canBeRemoved = $true
            foreach($saveValue in $saveValues)
            {
                if($name -eq $saveValue)
                {
                    $canBeRemoved = $false
                    break
                }
            }
            if($canBeRemoved)
            {
                [string]$data = (Get-ItemProperty -Path $key -Name $name).$name
                [System.Text.RegularExpressions.MatchCollection]$matches = [System.Text.RegularExpressions.Regex]::matches($data, "\""?(?<exePath>.+.exe)\""?", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                #
                # EXception will be throw if the condition is not content.
                #
                [string]$value = "$key $name"
                [string]$name = $name
                [string]$description = $localizationString.tooManyStartupPrograms_companyName_Unknown
                [bool]$needbeAdded = $true
                if($matches.Count -gt 0)
                {
                    try
                    {
                        [string]$exePath = $matches[0].Groups["exePath"].Value
                        $needbeAdded = NeedAddToList $exePath $inboxExeProductName
                        if($needbeAdded)
                        {
                            [string]$targetPath = [System.Environment]::ExpandEnvironmentVariables($exePath)
                            [System.Diagnostics.FileVersionInfo]$fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($targetPath)
                            [string]$showName = GetStartupApplicationShowName $fileVersionInfo
                            if(-not [string]::IsNullOrEmpty($showName))
                            {
                                $name = $showName
                            }
                            if(-not [string]::IsNullOrEmpty($fileVersionInfo.CompanyName))
                            {
                                $description = $fileVersionInfo.CompanyName
                            }
                        }
                    }
                    catch
                    {
                        WriteFunctionExceptionReport "RemoveStartupPrograms" $_
                    }
                }
                $description += " " + $data
                if($needbeAdded)
                {
                    $choices += @{"Name" = "$name"; "Description" = "$description"; "Value" = "$value"}
                }
            }
        }
    }

    #
    # check startup file
    #
    $startupFileArray = New-Object -TypeName System.Collections.ArrayList
    foreach($path in $linkPathArray)
    {
        if(Test-Path($path))
        {
            $fileArray = Get-ChildItem -Path $path
            if($fileArray -ne $null)
            {
                $startupFileArray += $fileArray
            }
        }
    }

    if($startupFileArray.Count -gt 0)
    {
        foreach($statupFile in $startupFileArray)
        {
            [string]$name = $statupFile.BaseName
            [string]$description = $localizationString.tooManyStartupPrograms_companyName_Unknown
            [bool]$needbeAdded = $true
            try
            {
                $shell =  New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($statupFile.FullName)
                if($shortcut -ne $null)
                {
                    $needbeAdded = NeedAddToList $shortcut.TargetPath $inboxExeProductName
                    if($needbeAdded)
                    {
                        [string]$targetPath = [System.Environment]::ExpandEnvironmentVariables($shortcut.TargetPath)
                        [System.Diagnostics.FileVersionInfo]$fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($targetPath)
                        [string]$showName = GetStartupApplicationShowName $fileVersionInfo
                        if(-not [string]::IsNullOrEmpty($showName))
                        {
                            $name = $showName
                        }
                        if(-not [string]::IsNullOrEmpty($fileVersionInfo.CompanyName))
                        {
                            $description = $fileVersionInfo.CompanyName
                        }
                        $description += " " + $shortcut.TargetPath + " " +$shortcut.Arguments
                }
                }
                else
                {
                    $description += " " + $statupFile.FullName
                }
            }
            catch
            {
                $description += " " + $statupFile.FullName
                WriteFunctionExceptionReport "RemoveStartupPrograms" $_
            }
            if($needbeAdded)
            {
                $choices += @{"Name" = $name; "Description" = $description; "Value" = $statupFile.FullName}
            }
        }
    }

    if($choices.Count -gt 0)
    {
        #
        # Deletes the values that the user choices
        #
        $values = Get-DiagInput -id $diagInputName -choice $choices
        if($values -eq $null)
        {
            return
        }
        #
        # delete and backup the registry keys that the user selected
        #
        $nameArray = New-Object System.Collections.ArrayList
        foreach($key in $keyArray)
        {
            #
            # Check whether the key is existed in registry
            #
            if(-not (Test-Path($key)))
            {
                Continue
            }
            $keyObj = Get-Item -Path $key
            $names =  $keyObj.Property
            foreach($name in $names)
            {
                foreach($value in $values)
                {
                    if("$key $name" -eq $value)
                    {
                        $nameArray += (Get-ItemProperty -Path $key -Name $name).$name
                        if($backup)
                        {
                            BackupStartupRegistryKey $key $name
                        }
                        Remove-itemProperty -Path $key -Name $name
                        break
                    }
                }
            }
        }

        #
        # delete and back the link files that the user selected
        #
        $fileArray = New-Object System.Collections.ArrayList
        if($startupFileArray.Count -gt 0)
        {
            foreach($file in $startupFileArray)
            {
                foreach($value in $values)
                {
                    if($file.FullName -eq $value)
                    {
                        $fileArray += $file
                        if($backup)
                        {
                            BackupStartupLinkFile $file
                        }
                        Remove-item -Path $file.FullName
                        break
                    }
                }
            }

        }

        if($nameArray.Count -gt 0)
        {
            $nameArray | select-object -Property @{Name=$localizationString.registryPrograms_programName; Expression={$_}} | convertto-xml | Update-DiagReport -id RegistryPrograms -name $localizationString.registryPrograms_removedProgram -verbosity Informational
        }

        if($fileArray.Count -gt 0)
        {
            $fileArray | select-object -Property @{Name=$localizationString.registryPrograms_programName; Expression={$_.FullName}} | convertto-xml | Update-DiagReport -id RegistryPrograms -name $localizationString.registryPrograms_removedProgram -verbosity Informational
        }
    }
}

#
# power mode
#

#get the power config

$methodDefinition = @"

using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Text;
    public sealed class PowerConfig
    {
        [Flags]
        public enum POWER_DATA_ACCESSOR
        {
            /// <summary>
            /// Check for overrides on AC power settings.
            /// </summary>
            ACCESS_AC_POWER_SETTING_INDEX = 0x0,
            /// <summary>
            /// Check for overrides on DC power settings.
            /// </summary>
            ACCESS_DC_POWER_SETTING_INDEX = 0x1,
            /// <summary>
            /// Check for restrictions on specific power schemes.
            /// </summary>
            ACCESS_SCHEME = 0x10,
            /// <summary>
            /// Check for restrictions on active power schemes.
            /// </summary>
            ACCESS_ACTIVE_SCHEME = 0x13,
            /// <summary>
            /// Check for restrictions on creating or restoring power schemes.
            /// </summary>
            ACCESS_CREATE_SCHEME = 0x14
        };

        public enum POWER_PLATFORM_ROLE
        {
            PlatformRoleUnspecified = 0,
            PlatformRoleDesktop = 1,
            PlatformRoleMobile = 2,
            PlatformRoleWorkstation = 3,
            PlatformRoleEnterpriseServer = 4,
            PlatformRoleSOHOServer = 5,
            PlatformRoleAppliancePC = 6,
            PlatformRolePerformanceServer = 7,
            PlatformRoleMaximum = 8
        };

        [System.Runtime.InteropServices.StructLayoutAttribute(System.Runtime.InteropServices.LayoutKind.Sequential)]
        public struct SYSTEM_POWER_CAPABILITIES
        {

            /// BOOLEAN->BYTE->unsigned char
            public byte PowerButtonPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte SleepButtonPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte LidPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte SystemS1;

            /// BOOLEAN->BYTE->unsigned char
            public byte SystemS2;

            /// BOOLEAN->BYTE->unsigned char
            public byte SystemS3;

            /// BOOLEAN->BYTE->unsigned char
            public byte SystemS4;

            /// BOOLEAN->BYTE->unsigned char
            public byte SystemS5;

            /// BOOLEAN->BYTE->unsigned char
            public byte HiberFilePresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte FullWake;

            /// BOOLEAN->BYTE->unsigned char
            public byte VideoDimPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte ApmPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte UpsPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte ThermalControl;

            /// BOOLEAN->BYTE->unsigned char
            public byte ProcessorThrottle;

            /// BYTE->unsigned char
            public byte ProcessorMinThrottle;

            /// BYTE->unsigned char
            public byte ProcessorMaxThrottle;

            /// BOOLEAN->BYTE->unsigned char
            public byte FastSystemS4;

            /// BYTE[3]
            [System.Runtime.InteropServices.MarshalAsAttribute(System.Runtime.InteropServices.UnmanagedType.ByValArray, SizeConst = 3, ArraySubType = System.Runtime.InteropServices.UnmanagedType.I1)]
            public byte[] spare2;

            /// BOOLEAN->BYTE->unsigned char
            public byte DiskSpinDown;

            /// BYTE[8]
            [System.Runtime.InteropServices.MarshalAsAttribute(System.Runtime.InteropServices.UnmanagedType.ByValArray, SizeConst = 8, ArraySubType = System.Runtime.InteropServices.UnmanagedType.I1)]
            public byte[] spare3;

            /// BOOLEAN->BYTE->unsigned char
            public byte SystemBatteriesPresent;

            /// BOOLEAN->BYTE->unsigned char
            public byte BatteriesAreShortTerm;

            /// BATTERY_REPORTING_SCALE[3]
            [System.Runtime.InteropServices.MarshalAsAttribute(System.Runtime.InteropServices.UnmanagedType.ByValArray, SizeConst = 3, ArraySubType = System.Runtime.InteropServices.UnmanagedType.Struct)]
            public BATTERY_REPORTING_SCALE[] BatteryScale;

            /// SYSTEM_POWER_STATE->_SYSTEM_POWER_STATE
            public SYSTEM_POWER_STATE AcOnLineWake;

            /// SYSTEM_POWER_STATE->_SYSTEM_POWER_STATE
            public SYSTEM_POWER_STATE SoftLidWake;

            /// SYSTEM_POWER_STATE->_SYSTEM_POWER_STATE
            public SYSTEM_POWER_STATE RtcWake;

            /// SYSTEM_POWER_STATE->_SYSTEM_POWER_STATE
            public SYSTEM_POWER_STATE MinDeviceWakeState;

            /// SYSTEM_POWER_STATE->_SYSTEM_POWER_STATE
            public SYSTEM_POWER_STATE DefaultLowLatencyWake;
        }

        public enum SYSTEM_POWER_STATE
        {

            /// PowerSystemUnspecified -> 0
            PowerSystemUnspecified = 0,

            /// PowerSystemWorking -> 1
            PowerSystemWorking = 1,

            /// PowerSystemSleeping1 -> 2
            PowerSystemSleeping1 = 2,

            /// PowerSystemSleeping2 -> 3
            PowerSystemSleeping2 = 3,

            /// PowerSystemSleeping3 -> 4
            PowerSystemSleeping3 = 4,

            /// PowerSystemHibernate -> 5
            PowerSystemHibernate = 5,

            /// PowerSystemShutdown -> 6
            PowerSystemShutdown = 6,

            /// PowerSystemMaximum -> 7
            PowerSystemMaximum = 7,
        }

        [System.Runtime.InteropServices.StructLayoutAttribute(System.Runtime.InteropServices.LayoutKind.Sequential)]
        public struct BATTERY_REPORTING_SCALE
        {

            /// DWORD->unsigned int
            public uint Granularity;

            /// DWORD->unsigned int
            public uint Capacity;
        }


        [DllImport("powrprof.dll")]
        private static extern UInt32 CallNtPowerInformation(
             Int32 InformationLevel,
             IntPtr lpInputBuffer,
             UInt32 nInputBufferSize,
             ref SYSTEM_POWER_CAPABILITIES lpOutputBuffer,
             UInt32 nOutputBufferSize
             );

        [DllImport("PowrProf.dll", CharSet = CharSet.Auto)]
        private static extern POWER_PLATFORM_ROLE PowerDeterminePlatformRole();

        /// <summary>
        /// Full call to method PowerSettingAccessCheck().
        /// </summary>
        /// <param name="AccessFlags">One or more check specifier flags</param>
        /// <param name="PowerGuid">The relevant Power Policy GUID</param>
        /// <returns></returns>
        [DllImport("PowrProf.dll")]
        [return: MarshalAs(UnmanagedType.U4)]
        private static extern UInt32 PowerSettingAccessCheck(
                                POWER_DATA_ACCESSOR AccessFlags,
                                [MarshalAs(UnmanagedType.LPStruct)] Guid PowerGuid
                                );

        private PowerConfig() { }
        [DllImport("PowrProf.dll")]
        private static extern uint PowerReadACValueIndex(
                                      uint RootPowerKey,
                                      ref Guid SchemeGuid,
                                      ref Guid SubGroupOfPowerSettingsGuid,
                                      ref Guid PowerSettingGuid,
                                      ref UInt32 Value
                               );

        [DllImport("PowrProf.dll")]
        private static extern uint PowerReadDCValueIndex(
                                      uint RootPowerKey,
                                      ref Guid SchemeGuid,
                                      ref Guid SubGroupOfPowerSettingsGuid,
                                      ref Guid PowerSettingGuid,
                                      ref UInt32 Value
                               );
        [DllImport("PowrProf.dll")]
        private static extern uint PowerWriteACValueIndex(
                                      uint RootPowerKey,
                                      ref Guid SchemeGuid,
                                      ref Guid SubGroupOfPowerSettingsGuid,
                                      ref Guid PowerSettingGuid,
                                      uint AcValueIndex
                               );

        [DllImport("PowrProf.dll")]
        private static extern uint PowerWriteDCValueIndex(
                                      uint RootPowerKey,
                                      ref Guid SchemeGuid,
                                      ref Guid SubGroupOfPowerSettingsGuid,
                                      ref Guid PowerSettingGuid,
                                      uint AcValueIndex
                               );


        [DllImport("PowrProf.dll")]
        private static extern uint PowerGetActiveScheme(
                                      uint UserRootPowerKey,
                                      ref IntPtr ActivePolicyGuid
                                    );
        [DllImport("PowrProf.dll")]
        private static extern uint PowerSetActiveScheme(
                                      uint UserRootPowerKey,
                                      ref Guid SchemeGuid
                                    );

        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerEnumerate(
                    uint RootPowerKey,
                    IntPtr SchemeGuid,
                    IntPtr SubGroupOfPowerSettingGuid,
                    UInt32 AcessFlags,
                    UInt32 Index,
                    ref Guid Buffer,
                    ref UInt32 BufferSize);

        public static Guid ActiveSchemeGuid()
        {
            IntPtr guidPtr = new IntPtr();
            uint res = PowerConfig.PowerGetActiveScheme(0, ref guidPtr);

            Guid ret = (Guid)Marshal.PtrToStructure(guidPtr, typeof(Guid));
            Marshal.FreeHGlobal(guidPtr);

            return ret;
        }

        public static uint SetPowerActiveSchemeGuid(ref Guid activeSchemeGuid)
        {
            uint res = 0;
            res = PowerConfig.PowerSetActiveScheme(0, ref activeSchemeGuid);
            return res;
        }

        public static uint ReadPowerSetting(bool ac,
                                ref Guid activeSchemeGuid,
                                ref Guid subGroupGuid,
                                ref Guid settingGuid,
                                ref UInt32 value)
        {
            uint res = 0;

            if (ac)
            {
                res = PowerConfig.PowerReadACValueIndex(0, ref activeSchemeGuid, ref subGroupGuid,
                                      ref settingGuid,
                                      ref value);
            }
            else
            {
                res = PowerConfig.PowerReadDCValueIndex(0, ref activeSchemeGuid, ref subGroupGuid,
                      ref settingGuid,
                      ref value);
            }

            return res;
        }

        public static uint WritePowerSetting(bool ac,
                                     ref Guid activeSchemeGuid,
                                     ref Guid subGroupGuid,
                                     ref Guid settingGuid,
                                     UInt32 newValue)
        {
            uint res = 0;
            if (ac)
            {
                res = PowerConfig.PowerWriteACValueIndex(0, ref activeSchemeGuid, ref subGroupGuid,
                                     ref settingGuid,
                                     newValue);
            }
            else
            {
                res = PowerConfig.PowerWriteDCValueIndex(0, ref activeSchemeGuid, ref subGroupGuid,
                                     ref settingGuid,
                                     newValue);
            }
            if (res == 0)
            {
                res = PowerConfig.PowerSetActiveScheme(0,
                                       ref activeSchemeGuid);
            }
            return res;
        }

        public static Guid BalancedPowerPlan()
        {
            Guid subgroup = new Guid("fea3413e-7e05-4911-9a71-700331f1c294");
            Guid setting = new Guid("245d8541-3943-4422-b025-13a784f679b7");

            Guid Buffer = new Guid();
            Guid BalancedGuid = new Guid();
            UInt32 SchemeIndex = 0;
            UInt32 BufferSize = (UInt32)Marshal.SizeOf(typeof(Guid));

            while (0 == PowerConfig.PowerEnumerate(0, IntPtr.Zero, IntPtr.Zero, 16, SchemeIndex, ref Buffer, ref BufferSize))
            {
                uint ACvalue = 0;
                uint DCvalue = 0;

                PowerConfig.ReadPowerSetting(true, ref Buffer, ref subgroup, ref setting, ref ACvalue);
                PowerConfig.ReadPowerSetting(false, ref Buffer, ref subgroup, ref setting, ref DCvalue);

                if ((2 == ACvalue) && (2 == DCvalue))
                {
                    BalancedGuid = Buffer;
                }
                SchemeIndex++;
            }
            return BalancedGuid;
        }

        public static UInt32 CheckPowerSetting(bool ac,Guid guid)
        {
            UInt32 result;
            if (ac)
            {
                result = PowerConfig.PowerSettingAccessCheck(POWER_DATA_ACCESSOR.ACCESS_AC_POWER_SETTING_INDEX, guid);
            }
            else
            {
                result = PowerConfig.PowerSettingAccessCheck(POWER_DATA_ACCESSOR.ACCESS_DC_POWER_SETTING_INDEX, guid);
            }
            return result;
        }

        public static UInt32 CheckActiveSchemeAccess()
        {
            UInt32 result;
            result = PowerConfig.PowerSettingAccessCheck(POWER_DATA_ACCESSOR.ACCESS_ACTIVE_SCHEME, new Guid());
            return result;
        }

        public static bool IsLaptop()
        {
            bool result = false;
            POWER_PLATFORM_ROLE platform_role = PowerDeterminePlatformRole();
            if (platform_role == POWER_PLATFORM_ROLE.PlatformRoleMobile)
            {
                result = true;
            }
            Console.WriteLine(platform_role);
            return result;
        }


        public static bool IsVideoDim()
        {
            SYSTEM_POWER_CAPABILITIES powercapabilityes = new SYSTEM_POWER_CAPABILITIES();
            uint result = CallNtPowerInformation(
                               4, //SystemPowerCapabilities
                               (IntPtr)null,
                               0,
                               ref powercapabilityes,
                               (UInt32)Marshal.SizeOf(new SYSTEM_POWER_CAPABILITIES()));
            if (result != 0)
            {
                return false;
            }

            if (powercapabilityes.VideoDimPresent == 1)
            {
                return true;
            }
            else
            {
                return false;
            }
        }

    }
    public class ScreenSaver
    {
        // Signatures for unmanaged calls
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool SystemParametersInfo(
           int uAction, int uParam, ref int lpvParam,
           int flags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool SystemParametersInfo(
           int uAction, int uParam, ref bool lpvParam,
           int flags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern int PostMessage(IntPtr hWnd,
           int wMsg, int wParam, int lParam);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr OpenDesktop(
           string hDesktop, int Flags, bool Inherit,
           uint DesiredAccess);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool CloseDesktop(
           IntPtr hDesktop);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool EnumDesktopWindows(
           IntPtr hDesktop, EnumDesktopWindowsProc callback,
           IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool IsWindowVisible(
           IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern IntPtr GetForegroundWindow();

        // Callbacks
        private delegate bool EnumDesktopWindowsProc(
           IntPtr hDesktop, IntPtr lParam);

        // Constants
        private const int SPI_GETSCREENSAVERACTIVE = 16;
        private const int SPI_SETSCREENSAVERACTIVE = 17;
        private const int SPI_GETSCREENSAVERTIMEOUT = 14;
        private const int SPI_SETSCREENSAVERTIMEOUT = 15;
        private const int SPI_GETSCREENSAVERRUNNING = 114;
        private const int SPIF_SENDWININICHANGE = 2;

        private const uint DESKTOP_WRITEOBJECTS = 0x0080;
        private const uint DESKTOP_READOBJECTS = 0x0001;
        private const int WM_CLOSE = 16;

        // Returns TRUE if the screen saver is active
        // (enabled, but not necessarily running).
        public static bool GetScreenSaverActive()
        {
            bool isActive = false;

            SystemParametersInfo(SPI_GETSCREENSAVERACTIVE, 0,
               ref isActive, 0);
            return isActive;
        }

        // Pass in TRUE(1) to activate or FALSE(0) to deactivate
        // the screen saver.
        public static void SetScreenSaverActive(int Active)
        {
            int nullVar = 0;

            SystemParametersInfo(SPI_SETSCREENSAVERACTIVE,
               Active, ref nullVar, SPIF_SENDWININICHANGE);
        }

        // Returns the screen saver timeout setting, in seconds
        public static Int32 GetScreenSaverTimeout()
        {
            Int32 value = 0;

            SystemParametersInfo(SPI_GETSCREENSAVERTIMEOUT, 0,
               ref value, 0);
            return value;
        }

        // Pass in the number of seconds to set the screen saver
        // timeout value.
        public static void SetScreenSaverTimeout(Int32 Value)
        {
            int nullVar = 0;

            SystemParametersInfo(SPI_SETSCREENSAVERTIMEOUT,
               Value, ref nullVar, SPIF_SENDWININICHANGE);
        }

        // Returns TRUE if the screen saver is actually running
        public static bool GetScreenSaverRunning()
        {
            bool isRunning = false;

            SystemParametersInfo(SPI_GETSCREENSAVERRUNNING, 0,
               ref isRunning, 0);
            return isRunning;
        }

        public static void StopScreenSaver()
        {
            IntPtr hDesktop = OpenDesktop("Screen-saver", 0,
               false, DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS);
            if (hDesktop != IntPtr.Zero)
            {
                EnumDesktopWindows(hDesktop, new
                   EnumDesktopWindowsProc(StopScreenSaverFunc),
                   IntPtr.Zero);
                CloseDesktop(hDesktop);
            }
            else
            {
                PostMessage(GetForegroundWindow(), WM_CLOSE,
                   0, 0);
            }
        }

        private static bool StopScreenSaverFunc(IntPtr hWnd,
           IntPtr lParam)
        {
            if (IsWindowVisible(hWnd))
                PostMessage(hWnd, WM_CLOSE, 0, 0);
            return true;
        }
    }
"@

Add-Type -TypeDefinition $methodDefinition
$powerconfig = [PowerConfig]

$ScreenSaver = [ScreenSaver]


function IsLaptop()
{
    try
    {
        return $powerconfig::IsLaptop()
    }
    catch
    {
        $_
    }
}

function IsVideoDim()
{
    try
    {
        return $powerconfig::IsVideoDim()
    }
    catch
    {
        $_
    }
}


function GetActiveSchemeGuid()
{
    try
    {
        $activeSchemeGuid = $powerconfig::ActiveSchemeGuid()
        return $activeSchemeGuid
    }
    catch
    {
        $_
    }
}

function SetActiveSchemeGuid([string]$ActiveSchemeGuid = $(throw "No Active Scheme Guid is specified"))
{
    try
    {
        $ActiveSchemeGuid = new-object system.Guid($ActiveSchemeGuid)
        $res = $powerconfig::SetPowerActiveSchemeGuid([ref]$ActiveSchemeGuid)
        return $res
    }
    catch
    {
        $_
    }
}

function Getpowersetting([bool]$isAC,[string]$subGroupGuid = $(throw "No subGroup Guid is specified"),[string]$settingGuid = $(throw "No setting Guid is specified"))
{
    try
    {
        $activeSchemeGuid = $powerconfig::ActiveSchemeGuid()
        $subGroupGuid = new-object system.Guid($subGroupGuid)
        $settingGuid = new-object system.Guid($settingGuid)
        $settingvalue = 0
        $res = $powerconfig::ReadPowerSetting($isAC,[ref]$activeSchemeGuid,[ref]$subGroupGuid,[ref]$settingGuid,[ref]$settingvalue)
        if($res -eq 0)
        {
            return $settingvalue
        }
    }
    catch
    {
        $_
    }
}

function GetBalancedPowerPlan()
{
    try
    {
        $BalancedPowerPlan = $powerconfig::BalancedPowerPlan()
        return $BalancedPowerPlan
    }
    catch
    {

    }

}

function CheckPowerSettingAccess([bool]$isAC,[string]$settingGuid = $(throw "No setting Guid is specified"))
{
    try
    {
        $settingGuid = new-object system.Guid($settingGuid)
        $result = $powerconfig::CheckPowerSetting($isAC,$settingGuid)
        if($result -eq 0)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
    catch
    {
        $_
    }
}

function CheckActiveSchemeAccess()
{
    try
    {
        $result = $powerconfig::CheckActiveSchemeAccess()
        if($result -eq 0)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
    catch
    {
        $_
    }
}

#
# Power plan type , balance 2, high perf 1, power saver 0
#
function Detectpowerplan([int]$powerplantype)
{
    [bool]$result = $false

    if(-not(CheckActiveSchemeAccess))
    {
        WriteFunctionExceptionReport "Detectpowerplan" "NotAccess"
        return $false
    }

    $subgroupguid = "fea3413e-7e05-4911-9a71-700331f1c294"
    $settingguid = "245d8541-3943-4422-b025-13a784f679b7"
    $AC_settingvalue = Getpowersetting $true $subgroupguid $settingguid
    $access_AC = CheckPowerSettingAccess $true $settingguid

    $DC_settingvalue = Getpowersetting $false $subgroupguid $settingguid
    $access_DC = CheckPowerSettingAccess $false $settingguid

    if(($AC_settingvalue -ne $null) -and ($DC_settingvalue -ne $null))
    {
        if((($AC_settingvalue -eq $powerplantype) -and $access_AC) -or (($DC_settingvalue -eq $powerplantype) -and $access_DC))
        {
            $regpath = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{025A5937-A6BE-4686-A844-36FE4BEC8B6D}"

            if(Test-Path $regpath)
            {
                $activeguid = GetActiveSchemeGuid

                $itemproperty = Get-ItemProperty $regpath "PreferredPlan"
                if($itemproperty -ne $null)
                {
                    $PreferredPlan = $itemproperty.PreferredPlan
                    if([string]::IsNullOrEmpty($PreferredPlan) -eq $false)
                    {
                        if($PreferredPlan -ne $activeguid)
                        {
                            $result = $true
                            return $result
                        }
                        else
                        {
                            $result = $false
                            return $result
                        }
                    }
                }
            }

            $result = $true
        }
    }
    return $result
}

function SetBalancedPowerPlan()
{
    $regpath = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{025A5937-A6BE-4686-A844-36FE4BEC8B6D}"

    $BalancedSchemeGuid = ""

    #if registry item PreferredPlan exist, retrieve the value
    if(Test-Path $regpath)
    {
        $itemproperty = Get-ItemProperty $regpath "PreferredPlan"

        if($itemproperty -ne $null)
        {
            $PreferredPlan = $itemproperty.PreferredPlan
            if([string]::IsNullOrEmpty($PreferredPlan) -eq $false)
            {
                $BalancedSchemeGuid = $PreferredPlan
            }
        }
    }

    $activeschemeguid = GetActiveSchemeGuid

    $activeschemeguid_original = $activeschemeguid

    # if balanced scheme guid is not retrieved from registry, get balanced guid from api
    if([string]::IsNullOrEmpty($BalancedSchemeGuid))
    {
        $BalancedSchemeGuid = GetBalancedPowerPlan
    }

    $res = SetActiveSchemeGuid($BalancedSchemeGuid)

    return $res
}

# Function to wait for expected service status
function WaitFor-ServiceStatus([string]$serviceName=$(throw "No service name is specified"), [ServiceProcess.ServiceControllerStatus]$serviceStatus=$(throw "No service status is specified"))
{
    [ServiceProcess.ServiceController]$sc = New-Object "ServiceProcess.ServiceController" $serviceName
    [TimeSpan]$timeOut = New-Object TimeSpan(0,0,0,5,0)
    $sc.WaitForStatus($serviceStatus, $timeOut)
}

function GetInboxExeProductName()
{
    $powershellPath = [Diagnostics.Process]::GetCurrentProcess().Path
    [System.Diagnostics.FileVersionInfo]$fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($powershellPath)
    return $fileVersionInfo.ProductName
}

function NeedAddToList([string]$exePath, [string]$inboxExeProductName)
{
    [string]$targetPath = [System.Environment]::ExpandEnvironmentVariables($exePath)
    [System.Diagnostics.FileVersionInfo]$fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($targetPath)
    if($fileVersionInfo.ProductName -eq $inboxExeProductName -and [string]::IsNullOrEmpty($fileVersionInfo.FileDescription))
    {
        return $false
    }
    else
    {
        return $true
    }
}

function GetStartupApplicationShowName([System.Diagnostics.FileVersionInfo]$fileVersionInfo)
{
    if($fileVersionInfo.ProductName -eq $inboxExeProductName)
    {
        $fileVersionInfo.FileDescription
    }
    else
    {
        $fileVersionInfo.ProductName
    }
}

