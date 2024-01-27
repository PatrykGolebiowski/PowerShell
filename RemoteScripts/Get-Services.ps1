<#
.SYNOPSIS
    This script retrieves information about services from one or multiple remote computers.

.DESCRIPTION
    'Get-Services.ps1' is a PowerShell script that allows users to gather detailed information about services running on remote computers.
    The script can connect to multiple computers, resolve their Fully Qualified Domain Names (FQDNs), and retrieve services information.
    It supports filtering out default system services and can output the results either to a CSV file or display them in a grid view.

.PARAMETER File
    -File <String>
        Specifies the path to a text file containing a list of computer names. Each computer name should be on a separate line.

.PARAMETER SaveToFile
    -SaveToFile <Boolean>
        Determines whether to save the output to a CSV file. If set to $true, the output is saved to 'Services_<date>.csv'; otherwise, it is displayed in a grid view.

.PARAMETER Computers
    -Computers <Array>
        Specifies an array of computer names to connect to and retrieve services information.

.PARAMETER SkipDefaultServices
    -SkipDefaultServices <Boolean>
        If set to $true, the script will skip default services (like those running under 'NT AUTHORITY' and 'LocalSystem'). Default is $true.

.EXAMPLE
    .\Get_Services_Private.ps1 -Computers @('Computer1', 'Computer2')
    Connects to 'Computer1' and 'Computer2' and retrieves information about their services, displaying the results in a grid view.

.EXAMPLE
    .\Get_Services_Private.ps1 -File "C:\Computers.txt" -SaveToFile $true
    Reads a list of computer names from 'C:\Computers.txt', retrieves services information, and saves the results to a CSV file.

.NOTES
    The script uses PowerShell remoting to connect to remote computers. Ensure that PowerShell remoting is enabled and accessible on the target computers.
    The user executing the script must have the necessary permissions to access and gather information from the remote computers.
    
    This script has been tested on Windows PowerShell 5.1 and PowerShell 7.

.LINK
    About_Remote_Troubleshooting - https://docs.microsoft.com/powershell/scripting/learn/remoting/about_remote_troubleshooting
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [String]$File = $null,

    [Parameter(Mandatory = $false)]
    [Boolean]$SaveToFile = $false,

    [Parameter(Mandatory = $false)]
    [Array]$Computers = $null,

    [Parameter(Mandatory = $false)]
    [Boolean]$SkipDefaultServices = $true
)


function Resolve-FQDN($ComputerName) {
    if(-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
        Write-Error "Unable to reach $ComputerName. Please check network connectivity."
        return $null
    }

    try {
        $computerSystemDetails = (Get-WmiObject win32_computersystem -ComputerName $ComputerName -ErrorAction Stop)
        $fqdn = $computerSystemDetails.DNSHostName + "." + $computerSystemDetails.Domain
    }
    catch {
        Write-Error "Failed to retrieve FQDN for $ComputerName. Error: $_"
        return $null
    }

    return $fqdn
}

function Get-ServicesRemotely($Computer, $ComputerFQDN, $SkipDefaultServices) {

    Write-Host "FQDN: $ComputerFQDN"

    try {
        $psSession = New-PSSession -ComputerName $ComputerFQDN -Name $Computer -ErrorAction Stop
    }
    catch {
        Write-Error -Message $_
        return
    }

    $scriptBlock = {
        param ($SkipDefaultServices)

        $services = Get-WmiObject -Class Win32_Service
        if ($SkipDefaultServices) {
            $services = $services | Where-Object { $_.StartName -notlike "NT AUTHORITY*" -and $_.StartName -ne "LocalSystem" -and $null -ne $_.StartName }
        }
        return $services
    }

    $sessionServices = Invoke-Command -Session $psSession -ScriptBlock $scriptBlock -ArgumentList $SkipDefaultServices

    $temp_result = @()
    foreach ($service in $sessionServices) {
        $service_details = [PSCustomObject]@{
            Computer = $Computer
            ServiceName = $service.Name
            State = $service.State
            RunAs = $service.StartName
            Description = $service.Description
        }

        $temp_result += $service_details
    }

    try {
        $psSession | Remove-PSSession
    }
    catch {
        Write-Error -Message $_
    }

    return $temp_result

}


function main() {

    $computerList = @()
    $result = @()
    $date = Get-Date -Format "dd_MM_yyyy"

    # Check if both Computers and File parameters are provided
    if ($Computers -and $File) {
        Write-Error "Both 'Computers' and 'File' parameters cannot be used simultaneously. Please use only one."
        return
    }

    if ($Computers) {
        $computerList = $Computers
    } elseif ($File) {
        $computerList = Get-Content -Path $File
    }

    ForEach ($computer in $computerList) {
        $computerFQDN = Resolve-FQDN -ComputerName $computer

        if ($null -ne $computerFQDN) {
            $result += Get-ServicesRemotely -Computer $computer -ComputerFQDN $computerFQDN -SkipDefaultServices $SkipDefaultServices
        }
    }

    if($SaveToFile) {
        $result | Export-Csv -Path ".\Services_$date.csv" -NoTypeInformation
    }
    else {
        $result | Out-GridView -Title "Services"
    }

}

main