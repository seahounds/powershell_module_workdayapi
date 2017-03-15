﻿function Update-WorkdayWorkerPhone {
<#
.SYNOPSIS
    Updates a Worker's phone number in Workday, only if it is different.

.DESCRIPTION
    Updates a Worker's phone number in Workday, only if it is different.
    Change requests are always recorded in Workday's audit log even when
    the number is the same. Unlike Set-WorkdayWorkerPhone, this cmdlet
    first checks the current phone number before requesting a change. 

.PARAMETER WorkerId
    The Worker's Id at Workday.

.PARAMETER WorkerType
    The type of ID that the WorkerId represents. Valid values
    are 'WID', 'Contingent_Worker_ID' and 'Employee_ID'.

.PARAMETER WorkPhone
    Sets the Workday primary Work Landline for a Worker. This cmdlet does not
    currently support other phone types. Also excepts the alias OfficePhone.

.PARAMETER Human_ResourcesUri
    Human_Resources Endpoint Uri for the request. If not provided, the value
    stored with Set-WorkdayEndpoint -Endpoint Human_Resources is used.


.PARAMETER Username
    Username used to authenticate with Workday. If empty, the value stored
    using Set-WorkdayCredential will be used.

.PARAMETER Password
    Password used to authenticate with Workday. If empty, the value stored
    using Set-WorkdayCredential will be used.

.EXAMPLE
    
Update-WorkdayWorkerPhone -WorkerId 123 -Number 1234567890

#>

	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
            ParameterSetName="Search",
            Position=0)]
		[ValidatePattern ('^[a-fA-F0-9\-]{1,32}$')]
		[string]$WorkerId,
        [Parameter(ParameterSetName="Search")]
		[ValidateSet('WID', 'Contingent_Worker_ID', 'Employee_ID')]
		[string]$WorkerType = 'Employee_ID',
        [Parameter(ParameterSetName="Search")]
		[string]$Human_ResourcesUri,
        [Parameter(ParameterSetName="Search")]
		[string]$Username,
        [Parameter(ParameterSetName="Search")]
		[string]$Password,
        [Parameter(Mandatory = $true,
            ParameterSetName="NoSearch")]
        [xml]$WorkerXml,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Number,
		[string]$Extension,
		[ValidateSet('HOME','WORK')]
        [string]$UsageType = 'WORK',
		[ValidateSet('Landline','Cell')]
        [string]$DeviceType = 'Landline',
        [switch]$Private,
        [switch]$Secondary
	)

    if ([string]::IsNullOrWhiteSpace($Human_ResourcesUri)) { $Human_ResourcesUri = $WorkdayConfiguration.Endpoints['Human_Resources'] }

    if ($PsCmdlet.ParameterSetName -eq 'NoSearch') {
        $current = Get-WorkdayWorkerPhone -WorkerXml $WorkerXml
        $WorkerType = 'WID'
        $workerReference = $WorkerXml.GetElementsByTagName('wd:Worker_Reference') | Select-Object -First 1
        $WorkerId = $workerReference.ID | where {$_.type -eq 'WID'} | Select-Object -ExpandProperty InnerText
    } else {
        $current = Get-WorkdayWorkerPhone -WorkerId $WorkerId -WorkerType $WorkerType -Human_ResourcesUri:$Human_ResourcesUri -Username:$Username -Password:$Password
    }

    function scrub ([string]$PhoneNumber) { $PhoneNumber -replace '[^\d]','' }

    $scrubbedProposedNumber = scrub $Number
    $scrubbedProposedExtention = scrub $Extension
    $scrubbedCurrentNumber = $null
    $scrubbedCurrentExtension = $null
    $currentMatch = $current |
     Where-Object {
        $_.UsageType -eq $UsageType -and
        $_.DeviceType -eq $DeviceType
        $_.Primary
    } | Select-Object -First 1
    if ($currentMatch -ne $null) {
        $scrubbedCurrentNumber = scrub $currentMatch.Number
        $scrubbedCurrentExtension = scrub $currentMatch.Extension
    }
    
    $msg = "Current [$scrubbedCurrentNumber] ext [$scrubbedCurrentExtension] {0} Proposed [$scrubbedProposedNumber] ext [$scrubbedProposedExtention]"
    $output = [pscustomobject][ordered]@{
        Success = $true
        Message = $msg -f 'matched'
        Xml     = $null
    }
    if (
        $currentMatch -ne $null -and (
            $scrubbedCurrentNumber -ne $scrubbedProposedNumber -or
            $scrubbedCurrentExtension -ne $scrubbedProposedExtention -or
            $currentMatch.Primary -eq -not $Secondary -or
            $currentMatch.Public -eq -not $Private
        )
    ) {
        $params = $PSBoundParameters
        $null = $params.Remove('WorkerXml')
        $null = $params.Remove('WorkerId')
        $null = $params.Remove('WorkerType')
        Write-Debug $params
        $output = Set-WorkdayWorkerPhone -WorkerId $WorkerId -WorkerType $WorkerType @params
        if ($output.Success) {
            $output.Message = $msg -f 'changed to'
        }
    }
    
    Write-Verbose $output.Message
    Write-Output $output
}
