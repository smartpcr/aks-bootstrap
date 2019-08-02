function SetTerraformValue {
    param (
        [string] $valueFile,
        [string] $name,
        [string] $value)

    $content = ""
    if (Test-Path $valueFile) {
        $content = Get-Content $valueFile
    }

    $regex = New-Object System.Text.RegularExpressions.Regex("$name\s*=\s*""?([^""]*)\""?")
    $value = $value.Replace("\", "\\") # fix windows path
    $replaceValue = "$name = ""$value"""
    $buffer = New-Object System.Text.StringBuilder

    if ($null -eq $content -or $content.Trim().Length -eq 0) {
        $buffer.AppendLine($replaceValue) | Out-Null
    }
    else {
        $match = $regex.Match($content)
        if ($match.Success) {
            $content | ForEach-Object {
                $line = $_
                if ($line -and $line.Length -gt 0) {
                    $line = $regex.Replace($line, $replaceValue)
                    $buffer.AppendLine($line) | Out-Null
                }
            }
        }
        else {
            $content | ForEach-Object {
                $line = $_
                if ($line) {
                    $buffer.AppendLine($line) | Out-Null
                }
            }
            $buffer.AppendLine($replaceValue) | Out-Null
        }
    }

    $buffer.ToString().TrimEnd() | Out-File $valueFile -Encoding ascii
    terraform fmt $valueFile | Out-Null
}

function PopulateTerraformProperties() {
    param(
        [object]$bootstrapValues
    )

    [array]$terraformSpnsFound = az ad sp list --display-name $bootstrapValues.terraform.servicePrincipal | ConvertFrom-Json
    if ($null -eq $terraformSpnsFound -or $terraformSpnsFound.Count -eq 0) {
        throw "Unable to find terraform spn '$($bootstrapValues.terraform.servicePrincipal)'"
    }
    $terraformSpn = $terraformSpnsFound[0]
    $terraformSpnPwd = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $bootstrapValues.terraform.servicePrincipalSecretName | ConvertFrom-Json

    $bootstrapValues.terraform["spn"] = @{
        appId = $terraformSpn.appId
        pwd = $terraformSpnPwd.value
    }
}