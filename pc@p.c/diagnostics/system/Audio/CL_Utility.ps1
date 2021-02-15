# Copyright © 2008, Microsoft Corporation. All rights reserved.


Import-LocalizedData -BindingVariable localizationString -FileName CL_LocalizationData

# Function to parse the the list with delimiter "/"
function Parse-List([string]$list = $(throw "No list is specified"))
{
    if($list -eq $null)
    {
        return $null
    }

    return $list.Split("/", [StringSplitOptions]::RemoveEmptyEntries)
}

# Function to get the audio device type name
function Get-DeviceTypeName([string]$deviceType = $(throw "No device type name is specified"))
{
    [string]$deviceTypeName = ""
    if([String]::IsNullOrEmpty($deviceType))
    {
        return $deviceTypeName
    }

    if($deviceType -eq "Speakers/Headphones/Headset Earphone")
    {
        $deviceTypeName = $localizationString.speaker + ", " + $localizationString.headset  + " " + $localizationString.or + " " + $localizationString.headphone
    }
    elseif ($deviceType -eq "microphone/Headset Microphone")
    {
        $deviceTypeName = $localizationString.microphone  + " " + $localizationString.or + " " + $localizationString.headset
    }

    return $deviceTypeName
}

function GetAbsolutionPath([string]$fileName = $(throw "No file name is specified"))
{
    if([string]::IsNullorEmpty($fileName))
    {
        throw "Invalid file name"
    }

    return Join-Path (Get-Location).Path $fileName
}

function GetSystemPath([string]$fileName = $(throw "No file name is specified"))
{
    if([string]::IsNullorEmpty($fileName))
    {
        throw "Invalid file name"
    }

     [string]$systemPath = [System.Environment]::SystemDirectory
     return Join-Path $systemPath $fileName
}

function GetRuntimePath([string]$fileName = $(throw "No file name is specified"))
{
    if([string]::IsNullorEmpty($fileName))
    {
        throw "Invalid file name"
    }

     [string]$runtimePath =  [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
     return Join-Path $runtimePath $fileName
}

# Function to import audio management types
function Import-AudioManager()
{
$typeDefination = @"

using System;
using System.Runtime.InteropServices;

[ComImport, Guid("870AF99C-171D-4f9e-AF0D-E63DF40C2BC9")]
public class IPolicyConfigClass { }

[Guid("F8679F50-850A-41cf-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPolicyConfig
{
    int GetMixFormat(string pszDeviceName, IntPtr ppFormat);

    int GetDeviceFormat(string pszDeviceName, bool bDefault, IntPtr ppFormat);

    int ResetDeviceFormat(string pszDeviceName);

    int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr MixFormat);

    int GetProcessingPeriod(string pszDeviceName, bool bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);

    int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);

    int GetShareMode(string pszDeviceName, IntPtr pMode);

    int SetShareMode(string pszDeviceName, IntPtr mode);

    int GetPropertyValue(string pszDeviceName, bool bFxStore, IntPtr key, IntPtr pv);

    int SetPropertyValue(string pszDeviceName, bool bFxStore, IntPtr key, IntPtr pv);

    int SetDefaultEndpoint(string pszDeviceName, ERole role);

    int SetEndpointVisibility(string pszDeviceName, bool bVisible);
}

public static class IPolicyConfigHelper
{
    private static IPolicyConfig iPolicyConfig = new IPolicyConfigClass() as IPolicyConfig;

    public static int SetEndpointVisibility(string pszDeviceName, bool bVisible)
    {
        return iPolicyConfig.SetEndpointVisibility(pszDeviceName, bVisible);
    }

    public static int SetDefaultEndpoint(string pszDeviceName, ERole role)
    {
        return iPolicyConfig.SetDefaultEndpoint(pszDeviceName, role);
    }
}

public enum ERole
{
    EConsole,
    EMultimedia,
    ECommunications,
    ERoleEnumCount
}
"@

    return (Add-Type -TypeDefinition $typeDefination -PassThru)
}

# Function to get interface IPolicyConfig
function Get-IPolicyConfig()
{
    return (Import-AudioManager)[2]
}

# Function to get enum ERole
function Get-ERole()
{
    return (Import-AudioManager)[3]
}

# Function to get the localized device name
function Get-DeviceName([string]$deviceType=$(throw "No device type is specified")) {
    [string]$deviceName = $localizationString.unknownAudioDevice

    if("Speakers/Headphones/Headset Earphone" -eq $deviceType) {
        $deviceName = $localizationString.audioPlayback
    }

    if("microphone/Headset Microphone" -eq $deviceType) {
        $deviceName = $localizationString.audioRecording
    }

    return $deviceName
}

# Function to get the audio endpoint state name
function Get-DeviceStateName([int]$stateCode=$(throw "No state code is specified")) {
    [string]$stateName = ""
    if(1 -eq $stateCode) {
        $stateName = $localizationString.stateEnabled
    } elseif (2 -eq $stateCode) {
        $stateName = $localizationString.stateDisabled
    } elseif (4 -eq $stateCode) {
        $stateName = $localizationString.stateNotPresent
    } elseif (8 -eq $stateCode) {
        $stateName = $localizationString.stateUnplugged
    } else {
        $stateName = $localizationString.stateUnknown
    }

    return $stateName
}