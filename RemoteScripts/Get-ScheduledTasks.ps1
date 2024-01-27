<#
.SYNOPSIS
    Retrieves scheduled tasks from one or multiple remote computers.

.DESCRIPTION
    This script connects to remote computers, resolves their Fully Qualified Domain Names (FQDNs), and retrieves information about their scheduled tasks.
    It supports filtering out default tasks, such as those located in "\Microsoft\" and the root path "\".
    The results can be exported to a CSV file or displayed in a grid view.

.PARAMETER File
    -File <String>
        Specifies the path to a text file containing a list of computer names. Each computer name should be on a separate line.

.PARAMETER SaveToFile
    -SaveToFile <Boolean>
        Determines whether to save the output to a CSV file. If set to $true, the output is saved to 'Scheduled_tasks_<date>.csv'; otherwise, it is displayed in a grid view.

.PARAMETER Computers
    -Computers <Array>
        Specifies an array of computer names to connect to and retrieve scheduled tasks information.

.PARAMETER SkipDefaultTasks
    -SkipDefaultTasks <Boolean>
        If set to $true, the script will skip default tasks, such as those in the "\Microsoft\" path and the root path "\". Default is $true.

.EXAMPLE
    .\Get-ScheduledTasks.ps1 -Computers @('Computer1', 'Computer2')
    Connects to 'Computer1' and 'Computer2', retrieves information about their scheduled tasks, and displays the results in a grid view.

.EXAMPLE
    .\Get-ScheduledTasks.ps1 -File "C:\Computers.txt" -SaveToFile $true
    Reads a list of computer names from 'C:\Computers.txt', retrieves scheduled tasks information, and saves the results to a CSV file.

.NOTES
    Ensure PowerShell remoting is enabled and accessible on the target computers for this script to function properly.
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
    [Boolean]$SkipDefaultTasks = $true
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

function Get-ScheduledTasksRemotely($Computer, $ComputerFQDN, $SkipDefaultTasks) {

    Write-Host "FQDN: $ComputerFQDN"

    try {
        $psSession = New-PSSession -ComputerName $ComputerFQDN -Name $Computer -ErrorAction Stop
    }
    catch {
        Write-Error -Message $_
        return
    }

    $scriptBlock = {
        param ($SkipDefaultTasks)

        $tasks = Get-ScheduledTask
        if ($SkipDefaultTasks) {
            $tasks = $tasks | Where-Object { ($_.TaskPath -notlike "*Microsoft*") -and ($_.TaskPath -notlike "\") }
        }
        return $tasks
    }

    $sessionTasks = Invoke-Command -Session $psSession -ScriptBlock $scriptBlock -ArgumentList $SkipDefaultTasks
    
    $temp_result = @()
    ForEach ($task in $sessionTasks) {

        $task_details = [PSCustomObject]@{
            Computer = $Computer
            TaskName = $task.TaskName
            Path = $task.TaskPath
            State = $task.State
            RunAs = $task.Principal.UserId
            Description = $task.Description
            Author = $task.Author
        }

        $temp_result += $task_details
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
            $result += Get-ScheduledTasksRemotely -Computer $computer -ComputerFQDN $computerFQDN -SkipDefaultTasks $SkipDefaultTasks
        }
    }

    if($SaveToFile) {
        $result | Export-Csv -Path ".\Scheduled_tasks_$date.csv" -NoTypeInformation
    }
    else {
        $result | Out-GridView -Title "Scheduled tasks"
    }

}

main