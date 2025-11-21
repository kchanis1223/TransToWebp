# Animated WebP converter (no infinite loop version)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$srcRoot = Join-Path $PSScriptRoot "Before"
$dstRoot = Join-Path $PSScriptRoot "Webp"
$toolDir = Join-Path $PSScriptRoot "tools"
$libwebpZipUri = "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2-windows-x64.zip"
$quality = 90          # 0~100 (higher -> bigger size)
$method = 6            # 0(faster)~6(slower but higher quality)
$frameDurationMs = 33  # per-frame duration (ms). 12fps≈83ms, 16fps≈63ms, 24fps≈42ms, 30fps≈33ms.
$loopCount = 1         # number of times to repeat animation. 0=infinite; 1 means play once with no extra repeats.
$exts = @(".png", ".jpg", ".jpeg")
$script:libwebpReady = $false
$tempArgsDir = Join-Path $toolDir "tmp"

function Ensure-Libwebp {
    if ($script:libwebpReady) { return }

    $hasImg2 = Get-Command "img2webp.exe" -ErrorAction SilentlyContinue
    $hasCwebp = Get-Command "cwebp.exe" -ErrorAction SilentlyContinue
    if ($hasImg2 -and $hasCwebp) { $script:libwebpReady = $true; return }

    $img2Local = Join-Path $toolDir "img2webp.exe"
    $cwebpLocal = Join-Path $toolDir "cwebp.exe"
    if ((Test-Path $img2Local) -and (Test-Path $cwebpLocal)) { $script:libwebpReady = $true; return }

    Write-Host "libwebp tools not found. Downloading..."
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    $zipPath = Join-Path $toolDir "libwebp.zip"
    Invoke-WebRequest -Uri $libwebpZipUri -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $toolDir -Force

    $foundImg2 = Get-ChildItem -Path $toolDir -Recurse -Filter "img2webp.exe" | Select-Object -First 1
    $foundCwebp = Get-ChildItem -Path $toolDir -Recurse -Filter "cwebp.exe" | Select-Object -First 1
    if (-not $foundImg2 -or -not $foundCwebp) {
        throw "img2webp.exe or cwebp.exe could not be located after download."
    }
    Copy-Item $foundImg2.FullName $img2Local -Force
    Copy-Item $foundCwebp.FullName $cwebpLocal -Force

    $script:libwebpReady = $true
}

function Get-ToolPath {
    param([string] $exeName)

    $cmd = Get-Command $exeName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    Ensure-Libwebp
    $localPath = Join-Path $toolDir $exeName
    if (-not (Test-Path $localPath)) {
        throw "$exeName not found even after downloading libwebp."
    }
    return $localPath
}

function Convert-DirectoriesToAnimatedWebp {
    param(
        [string] $sourceRoot,
        [string] $targetRoot
    )

    if (-not (Test-Path $sourceRoot)) {
        throw "Source folder '$sourceRoot' does not exist."
    }

    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
    $img2webp = Get-ToolPath -exeName "img2webp.exe"
    New-Item -ItemType Directory -Force -Path $tempArgsDir | Out-Null

    # Walk every directory (root + children) and find frame sequences
    $directories = @((Get-Item $sourceRoot)) + (Get-ChildItem -Path $sourceRoot -Recurse -Directory)

    foreach ($dir in $directories) {
        $frames = Get-ChildItem -Path $dir.FullName -File | Where-Object { $exts -contains $_.Extension.ToLower() } | Sort-Object Name
        if (-not $frames -or $frames.Count -eq 0) { continue }

        $relDir = $dir.FullName.Substring($sourceRoot.Length).TrimStart("\", "/")
        if ([string]::IsNullOrWhiteSpace($relDir)) {
            $relDir = "root"
        }
        $destFile = Join-Path $targetRoot ($relDir + ".webp")
        New-Item -ItemType Directory -Force -Path (Split-Path $destFile) | Out-Null

        # Use short names via hard links/copies to avoid Windows command-length limits
        $workDir = Join-Path $tempArgsDir ("wrk_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null

        $shortNames = New-Object System.Collections.Generic.List[string]
        $idx = 0
        foreach ($f in $frames) {
            $idx++
            $shortName = "f{0:D5}{1}" -f $idx, $f.Extension.ToLower()
            $shortPath = Join-Path $workDir $shortName
            try {
                New-Item -ItemType HardLink -Path $shortPath -Target $f.FullName -ErrorAction Stop | Out-Null
            }
            catch {
                Copy-Item -LiteralPath $f.FullName -Destination $shortPath -Force
            }
            $shortNames.Add($shortName)
        }

        $args = @("-loop", "$loopCount", "-d", "$frameDurationMs", "-q", "$quality", "-m", "$method", "-o", $destFile)
        $args += $shortNames

        Write-Host "Creating animated WebP (no infinite loop):" $destFile

        Push-Location $workDir
        try {
            & $img2webp @args | Write-Host
        }
        finally {
            Pop-Location
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Convert-DirectoriesToAnimatedWebp -sourceRoot $srcRoot -targetRoot $dstRoot
