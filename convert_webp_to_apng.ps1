Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$srcRoot = Join-Path $PSScriptRoot "Webp"
$dstRoot = Join-Path $PSScriptRoot "APNG"
$toolDir = Join-Path $PSScriptRoot "tools"
$ffmpegZipUri = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$libwebpZipUri = "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2-windows-x64.zip"
$plays = 0                 # 0=infinite loop, 1=play once
$compressionLevel = 9      # 0(fast)~9(best compression)
$overwriteExisting = $true # $true: overwrite existing output files
$defaultFrameDurationMs = 33
$script:ffmpegReady = $false
$script:libwebpReady = $false

function Ensure-Ffmpeg {
    if ($script:ffmpegReady) { return }

    $hasFfmpeg = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
    if ($hasFfmpeg) {
        $script:ffmpegReady = $true
        return
    }

    $ffmpegLocal = Join-Path $toolDir "ffmpeg.exe"
    if (Test-Path $ffmpegLocal) {
        $script:ffmpegReady = $true
        return
    }

    Write-Host "ffmpeg not found. Downloading..."
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null

    $zipPath = Join-Path $toolDir "ffmpeg.zip"
    $extractDir = Join-Path $toolDir "ffmpeg_dist"

    Invoke-WebRequest -Uri $ffmpegZipUri -OutFile $zipPath
    if (Test-Path $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $foundFfmpeg = Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
    if (-not $foundFfmpeg) {
        throw "ffmpeg.exe could not be located after download."
    }

    Copy-Item -LiteralPath $foundFfmpeg.FullName -Destination $ffmpegLocal -Force
    $script:ffmpegReady = $true
}

function Get-FfmpegPath {
    $cmd = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    Ensure-Ffmpeg
    $localPath = Join-Path $toolDir "ffmpeg.exe"
    if (-not (Test-Path $localPath)) {
        throw "ffmpeg.exe not found even after download."
    }
    return $localPath
}

function Ensure-LibwebpTools {
    if ($script:libwebpReady) { return }

    $animDumpCmd = Get-Command "anim_dump.exe" -ErrorAction SilentlyContinue
    $webpInfoCmd = Get-Command "webpinfo.exe" -ErrorAction SilentlyContinue
    if ($animDumpCmd -and $webpInfoCmd) {
        $script:libwebpReady = $true
        return
    }

    $animDumpLocal = Join-Path $toolDir "anim_dump.exe"
    $webpInfoLocal = Join-Path $toolDir "webpinfo.exe"
    if ((Test-Path $animDumpLocal) -and (Test-Path $webpInfoLocal)) {
        $script:libwebpReady = $true
        return
    }

    $embeddedAnimDump = Get-ChildItem -Path $toolDir -Recurse -Filter "anim_dump.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $embeddedWebpInfo = Get-ChildItem -Path $toolDir -Recurse -Filter "webpinfo.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($embeddedAnimDump -and $embeddedWebpInfo) {
        Copy-Item -LiteralPath $embeddedAnimDump.FullName -Destination $animDumpLocal -Force
        Copy-Item -LiteralPath $embeddedWebpInfo.FullName -Destination $webpInfoLocal -Force
        $script:libwebpReady = $true
        return
    }

    Write-Host "libwebp tools not found. Downloading..."
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null

    $zipPath = Join-Path $toolDir "libwebp.zip"
    Invoke-WebRequest -Uri $libwebpZipUri -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $toolDir -Force

    $foundAnimDump = Get-ChildItem -Path $toolDir -Recurse -Filter "anim_dump.exe" | Select-Object -First 1
    $foundWebpInfo = Get-ChildItem -Path $toolDir -Recurse -Filter "webpinfo.exe" | Select-Object -First 1
    if (-not $foundAnimDump -or -not $foundWebpInfo) {
        throw "anim_dump.exe or webpinfo.exe could not be located after download."
    }

    Copy-Item -LiteralPath $foundAnimDump.FullName -Destination $animDumpLocal -Force
    Copy-Item -LiteralPath $foundWebpInfo.FullName -Destination $webpInfoLocal -Force
    $script:libwebpReady = $true
}

function Get-LibwebpToolPath {
    param([string] $exeName)

    $cmd = Get-Command $exeName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    Ensure-LibwebpTools
    $localPath = Join-Path $toolDir $exeName
    if (-not (Test-Path $localPath)) {
        throw "$exeName not found even after downloading libwebp."
    }
    return $localPath
}

function Parse-WebpFrameDurationsMs {
    param(
        [string] $webpInfoPath,
        [string] $webpFilePath
    )

    $output = & $webpInfoPath $webpFilePath
    $durations = New-Object System.Collections.Generic.List[int]

    foreach ($line in $output) {
        if ($line -match "Duration:\s*(\d+)") {
            $durations.Add([int]$Matches[1])
        }
    }

    return $durations
}

function Convert-OneWebpToApng {
    param(
        [string] $ffmpegPath,
        [string] $animDumpPath,
        [string] $webpInfoPath,
        [string] $srcFile,
        [string] $destFile
    )

    $tempRoot = Join-Path $toolDir "tmp_apng"
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $workDir = Join-Path $tempRoot ("wrk_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    try {
        & $animDumpPath -folder $workDir -prefix "fr_" $srcFile | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "anim_dump failed for '$srcFile'. Exit code: $LASTEXITCODE"
        }

        $frames = @(Get-ChildItem -Path $workDir -File -Filter "fr_*.png" | Sort-Object Name)
        if ($frames.Count -eq 0) {
            throw "No frames were extracted from '$srcFile'."
        }

        $durationsMs = Parse-WebpFrameDurationsMs -webpInfoPath $webpInfoPath -webpFilePath $srcFile
        if ($durationsMs.Count -ne $frames.Count) {
            $durationsMs = New-Object System.Collections.Generic.List[int]
            for ($i = 0; $i -lt $frames.Count; $i++) {
                $durationsMs.Add($defaultFrameDurationMs)
            }
        }

        $concatFile = Join-Path $workDir "frames.txt"
        $concatLines = New-Object System.Collections.Generic.List[string]

        for ($i = 0; $i -lt $frames.Count; $i++) {
            $safePath = $frames[$i].FullName.Replace("'", "''")
            $seconds = [Math]::Max($durationsMs[$i], 1) / 1000.0
            $concatLines.Add("file '$safePath'")
            $concatLines.Add(("duration {0}" -f $seconds.ToString("0.######", [System.Globalization.CultureInfo]::InvariantCulture)))
        }

        # ffmpeg concat demuxer requires the last file to be repeated to honor the previous duration.
        $lastPath = $frames[$frames.Count - 1].FullName.Replace("'", "''")
        $concatLines.Add("file '$lastPath'")
        Set-Content -Path $concatFile -Value $concatLines -Encoding Ascii

        $args = @(
            "-v", "error",
            "-f", "concat",
            "-safe", "0",
            "-i", $concatFile,
            "-plays", "$plays",
            "-compression_level", "$compressionLevel"
        )

        if ($overwriteExisting) {
            $args += "-y"
        }
        else {
            $args += "-n"
        }

        $args += @("-f", "apng", $destFile)
        & $ffmpegPath @args

        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg failed converting '$srcFile'. Exit code: $LASTEXITCODE"
        }
    }
    finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Convert-WebpFilesToApng {
    param(
        [string] $sourceRoot,
        [string] $targetRoot
    )

    if (-not (Test-Path $sourceRoot)) {
        throw "Source folder '$sourceRoot' does not exist."
    }

    $webpFiles = @(Get-ChildItem -Path $sourceRoot -Recurse -File -Filter "*.webp")
    if ($webpFiles.Count -eq 0) {
        Write-Host "No .webp files found under '$sourceRoot'."
        return
    }

    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
    $ffmpeg = Get-FfmpegPath
    $animDump = Get-LibwebpToolPath -exeName "anim_dump.exe"
    $webpInfo = Get-LibwebpToolPath -exeName "webpinfo.exe"

    foreach ($file in $webpFiles) {
        $relPath = $file.FullName.Substring($sourceRoot.Length).TrimStart("\", "/")
        $destFile = Join-Path $targetRoot ([System.IO.Path]::ChangeExtension($relPath, ".png"))
        New-Item -ItemType Directory -Force -Path (Split-Path $destFile) | Out-Null

        Write-Host "Creating APNG:" $destFile
        Convert-OneWebpToApng -ffmpegPath $ffmpeg -animDumpPath $animDump -webpInfoPath $webpInfo -srcFile $file.FullName -destFile $destFile
    }
}

Convert-WebpFilesToApng -sourceRoot $srcRoot -targetRoot $dstRoot
