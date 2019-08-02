
function InitializeLogger() {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptFolder,
        [Parameter(Mandatory = $true)]
        [string] $ScriptName
    )

    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version Latest
    $ShouldCreateLogger = $false

    try {
        if ($null -eq $Global:ScriptName) {
            $ShouldCreateLogger = $true
        }
    }
    catch {
        $ShouldCreateLogger = $true
    }

    if ($ShouldCreateLogger) {
        $Global:ScriptName = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } else { $ScriptName }
        LogTitle -Message $Global:ScriptName

        [System.Collections.ArrayList]($Global:Steps) = New-Object System.Collections.ArrayList
        ($Global:Steps).Add(@{
                Step      = 0
                Name      = ""
                Indent    = 0
                StartTime = (Get-Date)
            }) | Out-Null
        [int]($Global:PreviousStepNumber) = 0
        [int]($Global:ChildStepNumber) = 0
        [Hashtable]($Global:Apps) = New-Object Hashtable

        $scriptFolderName = Split-Path $ScriptFolder -Leaf
        if ($null -eq $scriptFolderName -or $scriptFolderName -ne "scripts") {
            throw "Invalid script folder: '$ScriptFolder'"
        }
        $logFolder = Join-Path $ScriptFolder "log"
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
        $timeString = (Get-Date).ToString("yyyy-MM-dd-HHmmss")
        $logFile = Join-Path $logFolder "$($timeString).log"
        $Global:LogFile = $logFile
    }
}

function StartScope() {
    param(
        [string]$ScopeName,
        [bool]$IsChild = $false
    )

    [System.Collections.ArrayList]$Global:Steps = if ($Global:Steps) { $Global:Steps } else { New-Object System.Collections.ArrayList }
    $Global:PreviousStepNumber = if ($Global:PreviousStepNumber) { $Global:PreviousStepNumber } else { 0 }
    $indent = 0
    if (($Global:Steps).Count -gt 0) {
        $previousStepInfo = ($Global:Steps)[($Global:Steps).Count - 1]
        $Indent = $previousStepInfo.Indent
    }
    $StepInfo = @{
        Step      = if ($IsChild) { 1 } else { $Global:PreviousStepNumber + 1 }
        Name      = $ScopeName
        Indent    = if ($IsChild) { $indent + 1 } else { $indent }
        StartTime = (Get-Date)
    }
    ($Global:Steps).Add([object]$StepInfo) | Out-Null

    $indentation = "".PadLeft(2 * $StepInfo.Indent)
    $formatedMessage = "$($indentation)$($StepInfo.Step). $($StepInfo.Name) started - $($StepInfo.StartTime)"
    Add-Content -Path $Global:LogFile -Value $formatedMessage
    Write-Host $formatedMessage -ForegroundColor Green
    [int]($Global:ChildStepNumber) = 0
}

function FinishScope() {
    param(
        [bool]$IsChild = $false
    )

    [System.Collections.ArrayList]$Global:Steps = if ($Global:Steps) { $Global:Steps } else { New-Object System.Collections.ArrayList }
    if (($Global:Steps).Count -gt 0) {
        $currentStepInfo = ($Global:Steps)[($Global:Steps).Count - 1]
        ($Global:Steps).Remove($currentStepInfo)
        $StartTime = if ($currentStepInfo.StartTime) { $currentStepInfo.StartTime } else { Get-Date }
        $Span = New-TimeSpan -Start ([System.DateTime]($StartTime))
        $indentation = "".PadLeft(2 * $currentStepInfo.Indent)
        $formatedMessage = "$($indentation)$($currentStepInfo.Step). $($currentStepInfo.Name) finished - $($Span)`n"
        Add-Content -Path $Global:LogFile -Value $formatedMessage
        Write-Host $formatedMessage -ForegroundColor Green

        if ($IsChild) {
            if (($Global:Steps).Count -gt 0) {
                $parentStep = ($Global:Steps)[($Global:Steps).Count - 1]
                $Global:PreviousStepNumber = $parentStep.Step
            }
            else {
                $Global:PreviousStepNumber = 1
            }
        }
        else {
            $Global:PreviousStepNumber = $currentStepInfo.Step
        }
    }
}

function LogStep() {
    param(
        [string]$Message
    )

    [System.Collections.ArrayList]$Global:Steps = if ($Global:Steps) { $Global:Steps } else { New-Object System.Collections.ArrayList }
    $Script:PreviousStepNumber = if ($Global:ChildStepNumber) { $Global:ChildStepNumber } else { 0 }
    $currentStepNumber = $Global:ChildStepNumber + 1
    if (($Global:Steps).Count -gt 0) {
        $currentStepInfo = ($Global:Steps)[($Global:Steps).Count - 1]
        $indentation = "".PadLeft(2 * $currentStepInfo.Indent + 2)
        $formatedMessage = "$($indentation)$($currentStepNumber). $($Message)"
        Add-Content -Path $Global:LogFile -Value $formatedMessage
        Write-Host $formatedMessage -ForegroundColor Yellow
    }
    else {
        $formatedMessage = "$currentStepNumber. $($Message)"
        Add-Content -Path $Global:LogFile -Value $formatedMessage
        Write-Host $formatedMessage -ForegroundColor Yellow
    }
    $Global:ChildStepNumber = $currentStepNumber
}

function UsingScope() {
    [CmdletBinding()]
    param(
        [string] $ScopeName,
        [ScriptBlock]$ScriptBlock
    )

    try {
        StartScope -ScopeName $ScopeName
        . $ScriptBlock
    }
    finally {
        FinishScope
    }
}

function UsingChildScope() {
    [CmdletBinding()]
    param(
        [string] $ScopeName,
        [ScriptBlock]$ScriptBlock
    )

    try {
        StartScope -ScopeName $ScopeName -IsChild $true
        . $ScriptBlock
    }
    finally {
        FinishScope -IsChild $true
    }
}