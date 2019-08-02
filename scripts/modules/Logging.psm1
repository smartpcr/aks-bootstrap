
function Initialize() {
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
    Write-Host "$($indentation)$($StepInfo.Step). $($StepInfo.Name) started - $($StepInfo.StartTime)" -ForegroundColor Green
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
        Write-Host "$($indentation)$($currentStepInfo.Step). $($currentStepInfo.Name) finished - $($Span)`n" -ForegroundColor Green

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
        Write-Host "$($indentation)$($currentStepNumber). $($Message)" -ForegroundColor Yellow
    }
    else {
        Write-Host "$currentStepNumber. $($Message)" -ForegroundColor Yellow
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