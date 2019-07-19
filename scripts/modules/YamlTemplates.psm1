
function New-CrcTable {
    [uint32]$c = $null
    $crcTable = New-Object 'System.Uint32[]' 256

    for ($n = 0; $n -lt 256; $n++) {
        $c = [uint32]$n
        for ($k = 0; $k -lt 8; $k++) {
            if ($c -band 1) {
                $c = (0xEDB88320 -bxor ($c -shr 1))
            }
            else {
                $c = ($c -shr 1)
            }
        }
        $crcTable[$n] = $c
    }

    return $crcTable
}

function Update-Crc ([uint32]$crc, [byte[]]$buffer, [int]$length) {
    [uint32]$c = $crc

    if (-not($crcTable)) {
        $crcTable = New-CrcTable
    }

    for ($n = 0; $n -lt $length; $n++) {
        $c = ($crcTable[($c -bxor $buffer[$n]) -band 0xFF]) -bxor ($c -shr 8)
    }

    return $c
}

function GetCrc32 {
    <#
        .SYNOPSIS
            Calculate CRC.
        .DESCRIPTION
            This function calculates the CRC of the input data using the CRC32 algorithm.
        .EXAMPLE
            GetCrc32 $data
        .EXAMPLE
            $data | GetCrc32
        .NOTES
            C to PowerShell conversion based on code in https://www.w3.org/TR/PNG/#D-CRCAppendix

            Author: Øyvind Kallstad
            Date: 06.02.2017
            Version: 1.0
        .INPUTS
            byte[]
        .OUTPUTS
            uint32
        .LINK
            https://communary.net/
        .LINK
            https://www.w3.org/TR/PNG/#D-CRCAppendix

    #>
    [CmdletBinding()]
    param (
        # Array of Bytes to use for CRC calculation
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$String
    )

    $String = $String.Trim("`"")
    [byte[]]$InputObject = [System.Text.Encoding]::UTF8.GetBytes($String)

    $dataArray = @()
    $crcTable = New-CrcTable


    foreach ($item  in $InputObject) {
        $dataArray += $item
    }

    $inputLength = $dataArray.Length
    $hash = ((Update-Crc -crc 0xffffffffL -buffer $dataArray -length $inputLength) -bxor 0xffffffffL)
    return $hash
}

function GetYamlFolder() {

    $gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
        $gitRootFolder = Split-Path $gitRootFolder -Parent
    }
    $scriptFolder = Join-Path $gitRootFolder "Scripts"
    if (-not (Test-Path $scriptFolder)) {
        throw "Invalid script folder '$scriptFolder'"
    }

    $yamlsFolder = Join-Path $scriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }

    return $yamlsFolder
}

function RenderTemplate() {
    param(
        [string][Parameter(Mandatory = $true)] $File,
        [string][ValidateSet('None', 'YAML', 'CRC32')] $Encoding = "None"
    )

    $InputFile = Join-Path $(GetYamlFolder) $File
    if (-not (Test-Path $InputFile)) {
        throw "Unable to find file: $InputFile"
    }

    $Text = Get-Content $InputFile -Raw
    $Text = $Text.Trim("`"")

    switch ($Encoding) {
        'YAML' {
            # $Text =  $Text.Replace("\", "\\").Replace('"', '\"').Replace("`r", "\r").Replace("`n", "\n").Replace("`t", "\t")
            $Text = $Text.Replace("`n", "`n    ")
        }
        'CRC32' {
            return GetCrc32 -String $Text
        }
    }
    return "| `n    $Text"
}

function RenderFile() {
    param(
        [string][Parameter(Mandatory = $true)] $File,
        [string][ValidateSet('None', 'YAML', 'CRC32')] $Encoding = "None"
    )

    $InputFile = Join-Path $(GetYamlFolder) $File
    if (-not (Test-Path $InputFile)) {
        throw "Unable to find file: $InputFile"
    }

    $Text = Get-Content $InputFile -Raw
    $Text = $Text.Trim("`"")
    switch ($Encoding) {
        'YAML' {
            # $Text =  $Text.Replace("\", "\\").Replace('"', '\"').Replace("`r", "\r").Replace("`n", "\n").Replace("`t", "\t")
            $Text = $Text.Replace("`n", "`n    ")
        }
        'CRC32' {
            return GetCrc32 -String $Text
        }
    }
    return "| `n    $Text"
}
