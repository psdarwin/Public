Function Get-LastBoot {
    <#
    .SYNOPSIS
    RETRIEVE COMPUTER BOOT INFORMATION

    .DESCRIPTION 
    This script uses CIM and Get-WinEvent to retrieve time information for computer(s)
        last boot time
        system uptime
        build date
        etc.

    .PARAMETER ComputerName
    The name of the computer or computers

    .PARAMETER Credential
    Credential object to use to retrieve data

    .EXAMPLE
    Get-LastBoot -ComputerName SERVER
    This example returns boot time information for SERVER

    .EXAMPLE
    Get-LastBoot -ComputerName SERVER1,SERVER2,SERVER3 -Credential $Cred
    This example returns boot time information for the listed servers using the given credentials

    .INPUTS
    Parameters only

    .OUTPUTS
    This command produces no output.

    .NOTES   
    Author: Darwin Reiswig
    #>

    [CmdletBinding(
        PositionalBinding = $false
    )]
    Param(
        [Parameter(ValueFromPipeline, Position = 0, ParameterSetName = 'Name')]
            [alias("Name")]
            [alias("PSComputerName")]
            [string[]]$ComputerName,
        [Parameter()]
            [System.Management.Automation.PSCredential]$Credential
    )

    Begin {
        Write-Verbose "Begin $($MyInvocation.MyCommand)"
        [ScriptBlock]$GetEvents = {
            #Event 41 = The system has rebooted without cleanly shutting down first.
            Get-WinEvent -FilterHashtable @{Logname = 'System'; ID = 41 } -MaxEvents 1 -ErrorAction SilentlyContinue
            #Event 6008 = The previous system shutdown was unexpected.
            Get-WinEvent -FilterHashtable @{Logname = 'System'; ID = 6008 } -MaxEvents 1 -ErrorAction SilentlyContinue
            #Event 1074 = Normal Restart
            Get-WinEvent -FilterHashtable @{Logname = 'System'; ID = 1074 } -MaxEvents 1 -ErrorAction SilentlyContinue
        }
    }

    Process {
        foreach ($Computer in $ComputerName) {
            $Downtime = [timespan]0
            Write-Verbose "Retrieving CIM data for $Computer"
            if ($Credential) {
                $CIMData = Get-CimInstance -ClassName win32_operatingsystem -ComputerName $Computer -Credential $Credential
            } else {
                $CIMData = Get-CimInstance -ClassName win32_operatingsystem -ComputerName $Computer
            }

            Write-Verbose "Querying event log for $Computer for shutdown events."
            If ($Credential) {
                $EventList = @(Invoke-Command -ComputerName $Computer -ErrorAction Stop -ScriptBlock @GetEvents -Credential $Credential)
            } else {
                $EventList = @(Invoke-Command -ComputerName $Computer -ErrorAction Stop -ScriptBlock @GetEvents)
            }

            If ($EventList.count -gt 0) {
                Write-Verbose "Calculating downtime"
                $LastShutdownEvent = ($EventList | Sort-Object -Property timecreated -Descending -ErrorAction Stop)[0]
                $LastShutdownTime = $LastShutdownEvent.timecreated
                switch ($LastShutdownEvent.Id) {
                    41 { $LastShutdownType = "Unexpected" }
                    6008 { $LastShutdownType = "Unexpected" }
                    1074 {
                        $LastShutdownType = "Normal" 
                        $Downtime = $CIMData.LastBootUpTime - $LastShutdownTime
                    }
                    Default { $LastShutdownType = "Unknown" }
                }
            } else {
                Write-Verbose "Unable to acquire shutdown data from event log"
                $LastShutdownTime = [datetime]"1/1/1900"
                $LastShutdownType = "Unknown"
            }

            Write-Verbose "Compiling output data for $Computer"
            $Result = [pscustomobject]@{
                PSTypeName       = 'LastBoot'
                ComputerName     = $CIMData.CSName
                LastShutdownTime = $LastShutdownTime
                Downtime         = $Downtime
                DowntimeDays     = $Downtime.ToString("dd\.hh\:mm\:ss")
                LastBootUpTime   = $CIMData.LastBootUpTime
                Uptime           = $CIMData.LocalDateTime - $CIMData.LastBootUpTime
                UptimeDays       = ($CIMData.LocalDateTime - $CIMData.LastBootUpTime).ToString("dd\.hh\:mm\:ss")
                InstallDate      = $CIMData.InstallDate
                ShutdownType     = $LastShutdownType
            }
            Write-Output $Result
        }
    }

    End {
        Write-Verbose "End $($MyInvocation.MyCommand)"
    }
}