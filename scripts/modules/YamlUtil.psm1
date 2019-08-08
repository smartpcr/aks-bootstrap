

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

# Import-Module "$scriptFolder\Modules\powershell-yaml\powershell-yaml.psm1" -Force
Install-Module powershell-yaml -AllowClobber
Import-Module powershell-yaml -Force

function Get-EnvironmentSettings {
    param(
        [string] $EnvName = "dev",
        [string] $SpaceName = "xiaodong",
        [string] $EnvRootFolder,
        [Hashtable] $AdditionalSettings
    )

    $valuesOverride = Get-Content (Join-Path $EnvRootFolder "values.yaml") -Raw | ConvertFrom-Yaml
    if ($EnvName) {
        $envFolder = Join-Path $EnvRootFolder $EnvName
        $envValueYamlFile = Join-Path $envFolder "values.yaml"
        if (Test-Path $envValueYamlFile) {
            $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml
            Copy-YamlObject -fromObj $envValues -toObj $valuesOverride
        }

        if ($SpaceName) {
            $spaceFolder = Join-Path $envFolder $SpaceName
            $spaceValueYamlFile = Join-Path $spaceFolder "values.yaml"
            if (Test-Path $spaceValueYamlFile) {
                $spaceValues = Get-Content $spaceValueYamlFile -Raw | ConvertFrom-Yaml
                Copy-YamlObject -fromObj $spaceValues -toObj $valuesOverride
            }
        }
    }

    if ($null -ne $AdditionalSettings) {
        Copy-YamlObject -fromObj $AdditionalSettings -toObj $valuesOverride
    }

    $bootstrapTemplate = Get-Content "$EnvRootFolder\env.yaml" -Raw
    $bootstrapTemplate = Set-YamlValues -valueTemplate $bootstrapTemplate -settings $valuesOverride
    $bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml

    $propertiesOverride = GetProperties -subject $valuesOverride
    $targetProperties = GetProperties -subject $bootstrapValues
    $propertiesOverride | ForEach-Object {
        $propOverride = $_
        $newValue = GetPropertyValue -subject $valuesOverride -propertyPath $propOverride
        $targetPropFound = $targetProperties | Where-Object { $_ -eq $propOverride }

        if ($targetPropFound) {
            $existingValue = GetPropertyValue -subject $bootstrapValues -propertyPath $targetPropFound
            if ($null -ne $newValue -and $existingValue -ne $newValue) {
                SetPropertyValue -targetObject $bootstrapValues -propertyPath $targetPropFound -propertyValue $newValue
            }
        }
        else {
            # Write-Host "`tAdding property '$propOverride' value '$newValue'..." -ForegroundColor White
            SetPropertyValue -targetObject $bootstrapValues -propertyPath $propOverride -propertyValue $newValue
        }
    }

    return $bootstrapValues
}

function Copy-YamlObject {
    param (
        [object] $FromObj,
        [object] $ToObj
    )

    # handles array assignment
    if ($FromObj.GetType().IsGenericType -and $ToObj.GetType().IsGenericType) {
        HandleArrayOverride -FromObj $FromObj -ToObj $ToObj
        return
    }

    $FromObj.Keys | ForEach-Object {
        $name = $_
        $value = $FromObj.Item($name)

        if ($null -ne $value) {
            $tgtName = $ToObj.Keys | Where-Object { $_ -eq $name }
            if ($null -eq $tgtName) {
                $ToObj.Add($name, $value) | Out-Null
            }
            else {
                $tgtValue = $ToObj.Item($tgtName)
                if ($value -is [string] -or $value -is [int] -or $value -is [bool]) {
                    if ($value -ne $tgtValue) {
                        # Write-Host "Change value for '$tgtName' from '$tgtValue' to '$value'" -ForegroundColor Green
                        $ToObj[$tgtName] = $value
                    }
                }
                else {
                    if ($value.GetType().IsGenericType -and $tgtValue.GetType().IsGenericType) {
                        # Write-Host "handle array override: '$tgtName'" -ForegroundColor Yellow
                        HandleArrayOverride -FromObj $value -ToObj $tgtValue
                    }
                    else {
                        # Write-Host "handle child override: '$tgtName'" -ForegroundColor Yellow
                        Copy-YamlObject -fromObj $value -toObj $tgtValue
                    }
                }
            }
        }
    }
}

function HandleArrayOverride() {
    param(
        [object] $FromObj,
        [object] $ToObj
    )

    if ($null -ne $FromObj -and $FromObj.GetType().IsGenericType -and $null -ne $ToObj -and $ToObj.GetType().IsGenericType) {
        [array]$fromArray = [array]$FromObj
        [array]$toArray = [array]$ToObj
        if ($fromArray.Length -gt 0 -and $toArray.Length -gt 0) {
            $hasNameKey = $true
            $hasKey = $true
            $fromArray | ForEach-Object {
                if ($null -eq $_["name"]) {
                    $hasNameKey = $false
                }
                if ($null -eq $_["key"]) {
                    $hasKey = $false
                }
            }
            $toArray | ForEach-Object {
                if ($null -eq $_["name"]) {
                    $hasNameKey = $false
                }
                if ($null -eq $_["key"]) {
                    $hasKey = $false
                }
            }

            $keyPropName = $null
            if ($hasNameKey) {
                $keyPropName = "name"
            }
            elseif ($hasKey) {
                $keyPropName = "key"
            }

            if ($null -ne $keyPropName) {
                $unionList = New-Object System.Collections.ArrayList
                $toArray | ForEach-Object {
                    $toArrayChild = $_
                    $toName = $toArrayChild[$keyPropName]
                    $fromArrayChild = $fromArray | Where-Object { $_[$keyPropName] -eq $toName }
                    if ($null -ne $fromArrayChild) {
                        # Write-Host "Handle child override '$toName'" -ForegroundColor Yellow
                        Copy-YamlObject -FromObj $fromArrayChild -ToObj $toArrayChild
                    }
                    $unionList.Add($toArrayChild) | Out-Null
                }
                $fromArray | ForEach-Object {
                    $fromArrayChild = $_
                    $fromName = $fromArrayChild[$keyPropName]
                    $toArrayChild = $toArray | Where-Object { $_[$keyPropName] -eq $fromName }
                    if ($null -eq $toArrayChild) {
                        # Write-Host "Add new child '$fromName'" -ForegroundColor Green
                        $unionList.Add($fromArrayChild) | Out-Null
                    }
                }
                $toArray = $unionList.ToArray()
            }
            else {
                $toArray = $fromArray
            }
        }
    }
}

function Set-YamlValues {
    param (
        [string] $ValueTemplate,
        [object] $Settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}")
    $replacements = New-Object System.Collections.ArrayList
    $match = $regex.Match($ValueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value

        $found = GetPropertyValue -subject $Settings -propertyPath $searchKey
        if ($found) {
            if ($found -is [string] -or $found -is [int] -or $found -is [bool]) {
                $replaceValue = $found.ToString()
                $replacements.Add(@{
                        oldValue = $toBeReplaced
                        newValue = $replaceValue
                    }) | Out-Null
            }
            else {
                Write-Warning "Invalid value for path '$searchKey': $($found | ConvertTo-Json)"
            }
        }
        else {
            # Write-Warning "Unable to find value with path '$searchKey'"
        }

        $match = $match.NextMatch()
    }

    $replacements | ForEach-Object {
        $oldValue = $_.oldValue
        $newValue = $_.newValue
        # Write-Host "Replacing '$oldValue' with '$newValue'" -ForegroundColor Yellow
        $ValueTemplate = $ValueTemplate.Replace($oldValue, $newValue)
    }

    return $ValueTemplate
}

function ReplaceValuesInYamlFile {
    param(
        [string] $YamlFile,
        [string] $PlaceHolder,
        [string] $Value
    )

    $content = ""
    if (Test-Path $YamlFile) {
        $content = Get-Content $YamlFile
    }

    $pattern = "\{\{\s*\.Values.$PlaceHolder\s*\}\}"
    $buffer = New-Object System.Text.StringBuilder
    $content | ForEach-Object {
        $line = $_
        if ($line) {
            $line = $line -replace $pattern, $Value
            $buffer.AppendLine($line) | Out-Null
        }
    }

    $buffer.ToString() | Out-File $YamlFile -Encoding ascii
}

function GetPropertyValue {
    param(
        [object]$subject,
        [string]$propertyPath
    )

    $propNames = $propertyPath.Split(".")
    $currentObject = $subject
    for ($i = 0; $i -lt $propNames.Count; $i++) {
        $propName = $propNames[$i]
        if ($null -eq $currentObject -or $null -eq $propName) {
            return $null
        }
        if (IsPrimitiveValue -inputValue $currentObject) {
            Write-Warning "Unable to get property '$propName' using propertyPath='$propertyPath', current value is '$currentObject'"
            return $null
        }

        if ($null -ne $currentObject -and ([hashtable]$currentObject).ContainsKey($propName)) {
            $currentObject = $currentObject[$propName]

            if ($i -eq $propNames.Count - 1) {
                return $currentObject
            }
        }
        else {
            return $null
        }
    }
}

function GetProperties {
    param(
        [object] $subject,
        [string] $parentPropName
    )

    $props = New-Object System.Collections.ArrayList

    # handles array assignment
    if ($subject.GetType().IsGenericType) {
        return $props
    }

    $subject.Keys | ForEach-Object {
        $currentPropName = $_
        $value = $subject[$currentPropName]

        if ($null -ne $value) {
            $propName = $currentPropName
            if ($null -ne $parentPropName -and $parentPropName.Length -gt 0) {
                $propName = $parentPropName + "." + $currentPropName
            }

            if (IsPrimitiveValue -inputValue $value) {
                $props.Add($propName) | Out-Null
            }
            else {
                $nestedProps = GetProperties -subject $value -parentPropName $propName
                if ($null -ne $nestedProps) {
                    if ($nestedProps -is [string]) {
                        $props.Add([string]$nestedProps) | Out-Null
                    }
                    else {
                        $nestedProps | ForEach-Object {
                            $props.Add($_) | Out-Null
                        }
                    }
                }
            }
        }
    }

    return $props
}

function IsPrimitiveValue {
    param([object] $inputValue)

    if ($null -eq $inputValue) {
        return $true
    }

    $type = $inputValue.GetType()
    if ($type.IsPrimitive -or $type.IsEnum -or $type.Name -ieq "string") {
        return $true
    }

    return $false;
}

function SetPropertyValue {
    param(
        [object] $targetObject,
        [string] $propertyPath,
        [object] $propertyValue
    )

    if ($null -eq $targetObject) {
        return
    }

    $propNames = $propertyPath.Split(".")
    $currentValue = $targetObject
    $index = 0
    while ($index -lt $propNames.Count) {
        $propName = $propNames[$index]

        if ($index -eq $propNames.Count - 1) {
            # $oldValue = $currentValue[$propName]
            $currentValue[$propName] = $propertyValue
            # Write-Host "`tChange value for property '$propertyPath' from '$oldValue' to '$propertyValue'" -ForegroundColor White
            return
        }
        else {
            $currentValue = $currentValue[$propName]
            if ($null -eq $currentValue) {
                # Write-Warning "Unable to find property with path '$propertyPath'"
                return
            }
        }

        $index++
    }
}

function GetInnerFunctionExpression() {
    param(
        [string] $InputToEvaluate,
        [object] $InputObject = $null
    )

    $pipeFuncExprRegex = New-Object System.Text.RegularExpressions.Regex("\`$\(([^|`$]+)\s+\|\s+([^|\`$]+)\)")
    $funcExprRegex = New-Object System.Text.RegularExpressions.Regex("\`$\((\w+)\s*([^\|()\`$]*)\)")

    $match1 = $pipeFuncExprRegex.Match($InputToEvaluate)
    if ($match1.Success) {
        $match2 = $funcExprRegex.Match($match1.Groups[2].Value)
        if ($match2.Success) {
            return @{
                Value        = $match1.Value
                Feeder       = $match1.Groups[1].Value
                FunctionName = $match2.Groups[1].Value
                ArgList      = $match2.Groups[2].Value
            }
        }
        else {
            return @{
                Value        = $match1.Value
                Feeder       = $match1.Groups[1].Value
                FunctionName = $match1.Groups[2].Value
                ArgList      = $null
                Result       = $null
            }
        }
    }

    $match2 = $funcExprRegex.Match($InputToEvaluate)
    if ($match2.Success) {
        return @{
            Value        = $match2.Value
            FunctionName = $match2.Groups[1].Value
            ArgList      = $match2.Groups[2].Value
            Result       = $null
        }
    }

    if ($null -ne $InputObject) {
        $expressionBuilder = New-Object System.Text.StringBuilder
        $expressionBuilder.AppendLine("param(`$InputObject)") | Out-Null
        $expressionBuilder.AppendLine("return " + $InputToEvaluate) | Out-Null
        $scriptContent = $expressionBuilder.ToString()
        # Write-Host "Executing script block: `n$scriptContent`n" -ForegroundColor White
        $scriptBlock = [Scriptblock]::Create($scriptContent)
        $execResult = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $InputObject
        return @{
            Value        = $InputToEvaluate
            FunctionName = $null
            ArgList      = $null
            Result       = $execResult
        }
    }

    return $null
}

function Evaluate() {
    param(
        [string] $InputToEvaluate
    )

    $innerFunctionExpression = GetInnerFunctionExpression -InputToEvaluate $InputToEvaluate
    $evaluationResult = $null
    while ($null -ne $innerFunctionExpression) {
        if ($null -ne $innerFunctionExpression.Result) {
            $evaluationResult = $innerFunctionExpression.Result
        }
        else {
            $evaluationResult = EvaluateFunctionExpression -FunctionExpression $innerFunctionExpression -InputObject $evaluationResult
        }

        if ($evaluationResult) {
            if (IsPrimitiveValue -InputValue $evaluationResult) {
                # Write-Host "Replacing '$($innerFunctionExpression.Value)' with '$evaluationResult'" -ForegroundColor Yellow
                $InputToEvaluate = $InputToEvaluate.Replace($innerFunctionExpression.Value, "`"$evaluationResult`"")
                $innerFunctionExpression = GetInnerFunctionExpression -InputToEvaluate $InputToEvaluate
            }
            else {
                $InputObjectJson = $evaluationResult | ConvertTo-Json

                # Write-Host "Replacing '$($innerFunctionExpression.Value)' with json: `n$InputObjectJson`n" -ForegroundColor Yellow
                $InputToEvaluate = $InputToEvaluate.Replace($innerFunctionExpression.Value, "`$InputObject")
                $innerFunctionExpression = GetInnerFunctionExpression -InputToEvaluate $InputToEvaluate -InputObject $evaluationResult
            }
        }
        else {
            $innerFunctionExpression = $null
        }
    }

    return $InputToEvaluate
}

function EvaluateFunctionExpression() {
    param(
        [Parameter(Mandatory = $true)]
        [object] $FunctionExpression,
        [object] $InputObject = $null
    )

    $expressionBuilder = New-Object System.Text.StringBuilder
    if ($null -ne $InputObject) {
        $expressionBuilder.AppendLine("param(`$InputObject)") | Out-Null
    }
    $expressionBuilder.AppendLine("return " + $FunctionExpression.Value) | Out-Null
    $scriptContent = $expressionBuilder.ToString()
    # Write-Host "Executing script block: `n$scriptContent`n" -ForegroundColor White
    $scriptBlock = [Scriptblock]::Create($scriptContent)

    if ($null -ne $InputObject) {
        $execResult = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $InputObject
    }
    else {
        $execResult = Invoke-Command -ScriptBlock $scriptBlock
    }
    # Write-Host "Script result: $execResult" -ForegroundColor White

    return $execResult
}

function GetFunctionExpressions {
    param(
        [string] $YamlContent
    )

    $functionList = New-Object System.Collections.ArrayList
    $funcStartRegex = New-Object System.Text.RegularExpressions.Regex("\$\(")
    $lastFuncEndPos = 0
    $funcMatch = $funcStartRegex.Match($yamlContent, $lastFuncEndPos)
    while ($funcMatch.Success) {
        $parenthesisStack = New-Object System.Collections.Stack
        $pos = $funcMatch.Index
        $foundFuncExpr = $false

        while ($pos -lt $yamlContent.Length -and !$foundFuncExpr) {
            $currentChar = $yamlContent[$pos]
            if ($currentChar -eq "(") {
                $parenthesisStack.Push($currentChar)
            }
            elseif ($currentChar -eq ")") {
                if ($parenthesisStack.Count -lt 1) {
                    throw "Invalid function expression at $pos"
                }
                $parenthesisStack.Pop() | Out-Null

                if ($parenthesisStack.Count -eq 0) {
                    $lastFuncEndPos = $pos + 1
                    $functionExpr = $yamlContent.Substring($funcMatch.Index, $lastFuncEndPos - $funcMatch.Index)
                    if ($functionExpr -ne $YamlContent) {
                        # Write-Host "Found function: $functionExpr" -ForegroundColor White
                        $functionList.Add($functionExpr) | Out-Null
                    }

                    $lastFuncEndPos = $pos + 1
                    $foundFuncExpr = $true
                }
            }
            $pos++
        }

        $funcMatch = $funcStartRegex.Match($yamlContent, $lastFuncEndPos)
    }

    return @($functionList.ToArray())
}

function UpdateYamlWithEmbeddedFunctions {
    param(
        [string] $YamlFile
    )

    $yamlContent = Get-Content $YamlFile -Raw
    $funcExpressions = GetFunctionExpressions -YamlContent $yamlContent
    foreach ($functionInput in $funcExpressions) {
        $evaluatedValue = Evaluate -InputToEvaluate $functionInput
        if ($evaluatedValue -and $(IsPrimitiveValue -InputValue $evaluatedValue)) {
            $evaluatedValue = $evaluatedValue.Trim("`"")
            # Write-Host "$functionInput -> $evaluatedValue"
            $yamlContent = $yamlContent.Replace($functionInput, $evaluatedValue)
        }
        else {
            Write-Warning "Invalid value for function: $functionInput"
        }
    }

    $yamlContent | Out-File $YamlFile -Encoding utf8
}

function EvaluateEmbeddedFunctions() {
    param(
        [string] $YamlContent,
        [object] $InputObject
    )

    $funcRegex = New-Object System.Text.RegularExpressions.Regex("^\s*(\S+)\:\s*['`"](.*\`$\(.+\).+)['`"]$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $bindingRegex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $replacements = New-Object System.Collections.ArrayList

    $funcMatch = $funcRegex.Match($YamlContent)
    while ($funcMatch.Success) {
        $originalValue = $funcMatch.Groups[2].Value.Trim("`"").Trim("'")
        $settingValue = $originalValue
        $bindingMatch = $bindingRegex.Match($settingValue)
        $parameters = New-Object System.Collections.ArrayList

        while ($bindingMatch.Success) {
            $toBeReplaced = $bindingMatch.Value
            $searchKey = $bindingMatch.Groups[1].Value
            $found = GetPropertyValue -subject $InputObject -propertyPath $searchKey
            if ($null -ne $found) {
                if ($found -is [string] -or $found -is [int] -or $found -is [bool]) {
                    $replaceValue = $found.ToString()
                    $settingValue = $settingValue.Replace($toBeReplaced, $replaceValue)
                }
                else {
                    $paramName = "`$param" + ($parameters.Count + 1);
                    $param = @{
                        name  = $paramName
                        value = $found
                    }
                    $parameters.Add($param) | Out-Null
                    $settingValue = $settingValue.Replace($toBeReplaced, $paramName)
                }
            }
            else {
                # Write-Warning "Unable to find value with path '$searchKey'"
            }

            $bindingMatch = $bindingMatch.NextMatch()
        }

        $expressionBuilder = New-Object System.Text.StringBuilder
        if ($parameters.Count -gt 0) {
            $expressionBuilder.AppendLine("param(") | Out-Null
            $parameterIndex = 0
            $parameters | ForEach-Object {
                if ($parameterIndex -lt ($parameters.Count - 1)) {
                    $expressionBuilder.AppendLine("`t$($_.name),") | Out-Null
                    $parameterIndex++
                }
                else {
                    $expressionBuilder.AppendLine("`t$($_.name)") | Out-Null
                }
            }
            $expressionBuilder.AppendLine(")") | Out-Null
        }
        $expressionBuilder.AppendLine("return `"" + $settingValue + "`"") | Out-Null
        $scriptContent = $expressionBuilder.ToString()

        $scriptBlock = [Scriptblock]::Create($scriptContent)
        $execResult = $null
        if ($parameters.Count -gt 0) {
            $argList = New-Object System.Collections.ArrayList
            $parameters | ForEach-Object {
                $argList.Add($_.value) | Out-Null
            }
            $execResult = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $argList
        }
        else {
            $execResult = Invoke-Command -ScriptBlock $scriptBlock
        }

        if ($null -ne $execResult) {
            $replacements.Add(@{
                    oldValue = $originalValue
                    newValue = $execResult.ToString()
                }) | Out-Null
        }

        $funcMatch = $funcMatch.NextMatch()
    }

    $replacements | ForEach-Object {
        $oldValue = $_.oldValue
        $newValue = $_.newValue
        # Write-Host "Replacing '$oldValue' with '$newValue'" -ForegroundColor Yellow
        $YamlContent = $YamlContent.Replace($oldValue, $newValue)
    }

    return $YamlContent
}

function ConvertYamlToJson() {
    param(
        [Hashtable] $InputObject,
        [int] $Depth = 0,
        [int] $Indent = 2
    )

    $indentation = "".PadLeft($Depth * $Indent)
    $OutputBuilder = New-Object System.Text.StringBuilder
    $OutputBuilder.Append($indentation + "{") | Out-Null

    $isFirstElement = $true
    $InputObject.Keys | ForEach-Object {
        $name = $_
        $value = $InputObject[$name]

        if ($isFirstElement) {
            $OutputBuilder.Append("`n$($indentation)`"$($name)`": ") | Out-Null
            $isFirstElement = $false
        }
        else {
            $OutputBuilder.Append(",`n$($indentation)`"$($name)`": ") | Out-Null
        }

        if (IsPrimitiveValue -inputValue $value) {
            if ($value -is [string]) {
                $OutputBuilder.Append("`"$($value)`"") | Out-Null
            }
            elseif ($value -is [bool]) {
                if ($value -eq $true) {
                    $OutputBuilder.Append("true") | Out-Null
                }
                else {
                    $OutputBuilder.Append("false") | Out-Null
                }
            }
            elseif ($null -eq $value) {
                $OutputBuilder.Append("null") | Out-Null
            }
            else {
                $OutputBuilder.Append($value) | Out-Null
            }
        }
        elseif ($value.GetType().IsGenericType) {
            $OutputBuilder.Append("[") | Out-Null
            $isFirstItem = $true
            [array]$value | ForEach-Object {
                $arrayItem = $_
                if (IsPrimitiveValue -inputValue $arrayItem) {
                    if (!$isFirstItem) {
                        $OutputBuilder.Append(",") | Out-Null
                    }
                    else {
                        $isFirstItem = $false
                    }

                    if ($arrayItem -is [string]) {
                        $OutputBuilder.Append("`"$($arrayItem)`"") | Out-Null
                    }
                    elseif ($arrayItem -is [bool]) {
                        if ($arrayItem -eq $true) {
                            $OutputBuilder.Append("true") | Out-Null
                        }
                        else {
                            $OutputBuilder.Append("false") | Out-Null
                        }
                    }
                    elseif ($null -eq $arrayItem) {
                        $OutputBuilder.Append("null") | Out-Null
                    }
                    else {
                        $OutputBuilder.Append($arrayItem) | Out-Null
                    }
                }
                else {
                    $arrayItemJson = ConvertYamlToJson -InputObject $_ -Indent $Indent -Depth ($Depth + 1)
                    if ($isFirstItem) {
                        $isFirstItem = $false
                    }
                    else {
                        $arrayItemJson = "," + $arrayItemJson
                    }
                    $OutputBuilder.Append($arrayItemJson) | Out-Null
                }

            }
            $OutputBuilder.Append("`n" + $indentation + "]") | Out-Null
        }
        else {
            $childJson = ConvertYamlToJson -InputObject $value -Indent $Indent -Depth ($Depth + 1)
            $OutputBuilder.Append($childJson) | Out-Null
        }
    }

    $OutputBuilder.Append("`n" + $indentation + "}") | Out-Null

    [string]$json = $OutputBuilder.ToString()
    return $json
}