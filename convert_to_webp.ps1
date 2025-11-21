# Before/ 하위 시퀀스 이미지를 폴더별 단일 애니메이션 WebP로 변환해 Webp/에 저장
# Python/.NET 불필요, libwebp 도구(img2webp.exe, cwebp.exe) 없으면 자동 다운로드

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$srcRoot = Join-Path $PSScriptRoot "Before"
$dstRoot = Join-Path $PSScriptRoot "Webp"
$toolDir = Join-Path $PSScriptRoot "tools"
$libwebpZipUri = "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2-windows-x64.zip"
$quality = 90          # 0~100 품질 (높을수록 용량 증가)
$method = 6            # 0(빠름)~6(느리지만 품질↑)
$frameDurationMs = 33  # 프레임 지연(ms), 33쯤이면 30fps 정도
$exts = @(".png", ".jpg", ".jpeg")
$script:libwebpReady = $false
$tempArgsDir = Join-Path $toolDir "tmp"

function Ensure-Libwebp {
    if ($script:libwebpReady) { return }

    # PATH 또는 tools/ 캐시가 있으면 그대로 사용, 없으면 자동 다운로드
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

    # 루트와 모든 하위 폴더를 돌며 시퀀스를 탐색
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

        # 많은 프레임을 짧은 이름 하드링크/복사로 모아 Windows 명령줄 길이 제한 회피
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

        $args = @("-loop", "0", "-d", "$frameDurationMs", "-q", "$quality", "-m", "$method", "-o", $destFile)
        $args += $shortNames

        Write-Host "Creating animated WebP:" $destFile

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
