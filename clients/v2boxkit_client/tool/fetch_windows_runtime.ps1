$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Version = "v26.7.28"
$LibXrayArchive = "libxray-windows-x64.zip"
$LibXraySha256 = "0b270147c73448b4db6a050767c37cb217ba64459fa19e5e61f08fe3c2bdaafc"
$XrayArchive = "Xray-windows-64.zip"
$XraySha256 = "c7172078fca4711bcd92a4774dcd1822544579c58816197575c47533317fd8d1"

$ProjectDirectory = Split-Path -Parent $PSScriptRoot
$OutputDirectory = Join-Path $ProjectDirectory "windows\native\windows\x64"
$TemporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
    "v2boxkit-runtime-" + [System.Guid]::NewGuid().ToString("N")
)

function Get-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    Invoke-WebRequest -Uri $Url -OutFile $Path
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($Actual -ne $ExpectedSha256) {
        throw "Checksum mismatch for $Path. Expected $ExpectedSha256, got $Actual"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $TemporaryDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    $LibXrayPath = Join-Path $TemporaryDirectory $LibXrayArchive
    Get-VerifiedArchive `
        -Url "https://github.com/XTLS/libXray/releases/download/$Version/$LibXrayArchive" `
        -Path $LibXrayPath `
        -ExpectedSha256 $LibXraySha256
    $LibXrayExtracted = Join-Path $TemporaryDirectory "libxray"
    Expand-Archive -LiteralPath $LibXrayPath -DestinationPath $LibXrayExtracted
    Copy-Item `
        -LiteralPath (Join-Path $LibXrayExtracted "libxray-windows-x64\libXray.dll") `
        -Destination (Join-Path $OutputDirectory "libXray.dll") `
        -Force

    $XrayPath = Join-Path $TemporaryDirectory $XrayArchive
    Get-VerifiedArchive `
        -Url "https://github.com/XTLS/Xray-core/releases/download/$Version/$XrayArchive" `
        -Path $XrayPath `
        -ExpectedSha256 $XraySha256
    $XrayExtracted = Join-Path $TemporaryDirectory "xray"
    Expand-Archive -LiteralPath $XrayPath -DestinationPath $XrayExtracted
    Copy-Item `
        -LiteralPath (Join-Path $XrayExtracted "wintun.dll") `
        -Destination (Join-Path $OutputDirectory "wintun.dll") `
        -Force

    Write-Host "Installed Windows runtime files to $OutputDirectory ($Version)"
}
finally {
    if (Test-Path -LiteralPath $TemporaryDirectory) {
        Remove-Item -LiteralPath $TemporaryDirectory -Recurse -Force
    }
}
