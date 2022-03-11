Function Get-LastBoot
{
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
    The name of the computer

    .EXAMPLE
    Get-NRECALastBoot -ComputerName SERVER
    This example returns boot time information for SERVER

    .EXAMPLE
    Get-NRECALastBoot -ComputerName SERVER1,SERVER2,SERVER3
    This example returns boot time information for the listed servers

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
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0, ParameterSetName = 'Name')]
        [alias("Name")]
        [alias("PSComputerName")]
        [string[]]$ComputerName
    )

    Begin {
        Write-Verbose "Begin $($MyInvocation.MyCommand)"
    }

    Process {
        foreach ($Computer in $ComputerName) {
            Write-Verbose "Retrieving CIM data for $Computer"
            $CIMData = Get-NRECACimInstance -ClassName win32_operatingsystem -ComputerName $Computer
            Write-Verbose "Querying event log for $Computer for shutdown events."
            try {
                $LastShutdownEvent = Invoke-Command -ComputerName $Computer -ErrorAction Stop -ScriptBlock {
                    $EventList = @()
                    #The system has rebooted without cleanly shutting down first.
                    $EventList += Get-WinEvent -FilterHashtable @{Logname = 'System'; ID = 41 }  -MaxEvents 1 -ErrorAction SilentlyContinue
                    #The previous system shutdown  was unexpected.
                    $EventList += Get-WinEvent -FilterHashtable @{Logname = 'System'; ID = 6008 }  -MaxEvents 1 -ErrorAction SilentlyContinue
                    #Normal Restart
                    $EventList += Get-WinEvent -FilterHashtable @{Logname = 'System'; ID = 1074 }  -MaxEvents 1 -ErrorAction SilentlyContinue
                    ($EventList | Sort-Object -Property timecreated -Descending -ErrorAction Stop)[0]
                }
                Write-Verbose "Calculating downtime"
                $LastShutdownTime = $LastShutdownEvent.timecreated
                switch ($LastShutdownEvent.Id) {
                    41 { $LastShutdownType = "Unexpected" }
                    6008 { $LastShutdownType = "Unexpected" }
                    1074 { $LastShutdownType = "Normal" }
                    Default { $LastShutdownType = "Unknown" }
                }
                $Downtime = $CIMData.LastBootUpTime - $LastShutdownTime
            }
            catch {
                Write-Verbose "Unable to acquire shutdown data from event log"
                $LastShutdownTime = [datetime]"1/1/1900"
                $LastShutdownType = "Unknown"
                $Downtime = [timespan]0
            }
            
            Write-Verbose "Compiling output data for $Computer"
            $Result = [pscustomobject]@{
                PSTypeName       = 'NRECA.LastBoot'
                ComputerName     = $Computer
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
