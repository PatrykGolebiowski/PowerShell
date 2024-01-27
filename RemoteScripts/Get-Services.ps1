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