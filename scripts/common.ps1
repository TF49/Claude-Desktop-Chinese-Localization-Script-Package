Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Web.Extensions

function Read-Utf8Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function New-JsonSerializer {
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = 67108864
    return $serializer
}

function Read-JsonObject {
    param([string]$Path)
    $serializer = New-JsonSerializer
    return $serializer.DeserializeObject((Read-Utf8Text -Path $Path))
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Value
    )
    $json = $Value | ConvertTo-Json -Depth 10
    Write-Utf8Text -Path $Path -Content ($json + [Environment]::NewLine)
}

function Get-ProjectRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

function Get-Config {
    $rawConfig = Read-JsonObject -Path (Join-Path (Get-ProjectRoot) "config.json")
    return Resolve-ConfigPaths -Config $rawConfig
}

function Expand-EnvPath {
    param([string]$Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Add-UniqueString {
    param(
        [System.Collections.ArrayList]$Target,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $Target.Contains($Value)) {
        [void]$Target.Add($Value)
    }
}

function Test-InstallRootCandidate {
    param(
        [string]$InstallRoot,
        $Config
    )
    if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
        return $false
    }
    if (-not $Config.ContainsKey("resourceRelativePaths")) {
        return $true
    }

    foreach ($key in $Config["resourceRelativePaths"].Keys) {
        $path = Join-Path $InstallRoot $Config["resourceRelativePaths"][$key]
        if ($key -like "*Dir") {
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                return $false
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                return $false
            }
        }
    }

    return $true
}

function Resolve-CandidateByParentEnumeration {
    param([string]$ExpandedCandidate)
    $resolved = New-Object System.Collections.ArrayList
    $normalizedCandidate = $ExpandedCandidate -replace "/", "\"
    $wildcardPattern = '^(?<parent>.+)\\(?<leaf>[^\\]*[*?][^\\]*)\\(?<suffix>.+)$'
    $match = [System.Text.RegularExpressions.Regex]::Match($normalizedCandidate, $wildcardPattern)
    if (-not $match.Success) {
        return @($resolved)
    }

    $parent = $match.Groups["parent"].Value
    $leafPattern = $match.Groups["leaf"].Value
    $suffix = $match.Groups["suffix"].Value

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @($resolved)
    }

    foreach ($directory in Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue) {
        if ($directory.Name -notlike $leafPattern) {
            continue
        }

        $candidate = Join-Path $directory.FullName $suffix
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            Add-UniqueString -Target $resolved -Value $candidate
        }
    }

    return @($resolved)
}

function Resolve-InstallCandidates {
    param($Config)
    $resolved = New-Object System.Collections.ArrayList
    foreach ($candidate in $Config["installCandidates"]) {
        $expanded = Expand-EnvPath -Path $candidate
        $matches = @(Resolve-Path -Path $expanded -ErrorAction SilentlyContinue)
        foreach ($match in $matches) {
            if (Test-Path -LiteralPath $match.Path -PathType Container) {
                Add-UniqueString -Target $resolved -Value $match.Path
            }
        }

        foreach ($enumeratedCandidate in Resolve-CandidateByParentEnumeration -ExpandedCandidate $expanded) {
            Add-UniqueString -Target $resolved -Value $enumeratedCandidate
        }
    }

    return @($resolved | Sort-Object -Unique)
}

function Resolve-InstallRoot {
    param($Config)
    $candidates = @(Resolve-InstallCandidates -Config $Config)
    foreach ($candidate in $candidates) {
        if (Test-InstallRootCandidate -InstallRoot $candidate -Config $Config) {
            return $candidate
        }
    }

    $expandedCandidates = @($Config["installCandidates"] | ForEach-Object { Expand-EnvPath -Path $_ })
    throw "未找到受支持的 Claude Desktop 安装目录。候选路径: $($expandedCandidates -join '; ')"
}

function Convert-ToAbsolutePathMap {
    param(
        [string]$InstallRoot,
        $RelativeMap
    )
    $resolved = @{}
    foreach ($key in $RelativeMap.Keys) {
        $resolved[$key] = Join-Path $InstallRoot $RelativeMap[$key]
    }
    return $resolved
}

function Resolve-ConfigPaths {
    param($Config)
    $resolvedConfig = @{}
    foreach ($key in $Config.Keys) {
        $resolvedConfig[$key] = $Config[$key]
    }

    $installRoot = Resolve-InstallRoot -Config $Config
    $resolvedConfig["supportedInstallRoot"] = $installRoot

    if ($Config.ContainsKey("resourceRelativePaths")) {
        $resolvedConfig["resourceChecks"] = Convert-ToAbsolutePathMap -InstallRoot $installRoot -RelativeMap $Config["resourceRelativePaths"]
    }
    if ($Config.ContainsKey("applyRelativePaths")) {
        $resolvedConfig["applyTargets"] = Convert-ToAbsolutePathMap -InstallRoot $installRoot -RelativeMap $Config["applyRelativePaths"]
    }

    return $resolvedConfig
}

function Get-Patches {
    return Read-JsonObject -Path (Join-Path (Get-ProjectRoot) "patches\main-ui-patches.json")
}

function Get-VerificationTargets {
    return Read-JsonObject -Path (Join-Path (Get-ProjectRoot) "locales\verification-targets.json")
}

function Get-ProjectArtifacts {
    $projectRoot = Get-ProjectRoot
    return @{
        RootLocale = Join-Path $projectRoot "locales\root-zh-CN.json"
        IonLocale = Join-Path $projectRoot "locales\ion-zh-CN.json"
        IonLocaleZst = Join-Path $projectRoot "locales\ion-zh-CN.json.zst"
        IonOverrides = Join-Path $projectRoot "locales\ion-zh-CN.overrides.json"
        IonOverridesZst = Join-Path $projectRoot "locales\ion-zh-CN.overrides.json.zst"
        StatsigLocale = Join-Path $projectRoot "locales\statsig\zh-CN.json"
        StatsigLocaleZst = Join-Path $projectRoot "locales\statsig\zh-CN.json.zst"
        VerificationTargets = Join-Path $projectRoot "locales\verification-targets.json"
        PatchedAssetsDir = Join-Path $projectRoot "patched-assets\v1"
    }
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Description,
        [switch]$Directory
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description 不存在或无法访问: $Path"
    }
    if ($Directory -and -not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Description 不是目录: $Path"
    }
    if (-not $Directory -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description 不是文件: $Path"
    }
}

function Assert-ProjectArtifacts {
    param($Artifacts)
    foreach ($key in $Artifacts.Keys) {
        if ($key -like "*Dir") {
            Assert-PathExists -Path $Artifacts[$key] -Description "项目资源 $key" -Directory
        }
        else {
            Assert-PathExists -Path $Artifacts[$key] -Description "项目资源 $key"
        }
    }
}

function Assert-SupportedInstallation {
    param($Config)
    Assert-PathExists -Path $Config["supportedInstallRoot"] -Description "Claude Desktop 目标目录" -Directory

    foreach ($key in $Config["resourceChecks"].Keys) {
        $path = $Config["resourceChecks"][$key]
        if ($key -like "*Dir") {
            Assert-PathExists -Path $path -Description "目标资源 $key" -Directory
        }
        else {
            Assert-PathExists -Path $path -Description "目标资源 $key"
        }
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-BackupRoot {
    param($Config)
    return Join-Path (Get-ProjectRoot) $Config["backupDirName"]
}

function Get-Timestamp {
    return Get-Date -Format "yyyyMMdd-HHmmss"
}

function New-BackupRunDirectory {
    param($Config)
    $backupRoot = Get-BackupRoot -Config $Config
    Ensure-Directory -Path $backupRoot
    $runDir = Join-Path $backupRoot (Get-Timestamp)
    Ensure-Directory -Path $runDir
    return $runDir
}

function Get-LatestBackupDirectory {
    param($Config)
    $backupRoot = Get-BackupRoot -Config $Config
    Assert-PathExists -Path $backupRoot -Description "备份目录" -Directory
    $latest = Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object Name | Select-Object -Last 1
    if ($null -eq $latest) {
        throw "未找到可回滚的备份。"
    }
    return $latest.FullName
}

function Backup-File {
    param(
        [string]$Source,
        [string]$BackupDir
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }
    Ensure-Directory -Path $BackupDir
    $destination = Join-Path $BackupDir ([System.IO.Path]::GetFileName($Source))
    try {
        Copy-Item -LiteralPath $Source -Destination $destination -Force
    }
    catch [System.IO.IOException] {
        $bytes = [System.IO.File]::ReadAllBytes($Source)
        [System.IO.File]::WriteAllBytes($destination, $bytes)
    }
}

function Restore-DirectoryFiles {
    param(
        [string]$SourceDir,
        [string]$DestinationDir
    )
    $restored = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        return $restored
    }
    Ensure-Directory -Path $DestinationDir
    foreach ($item in Get-ChildItem -LiteralPath $SourceDir -File) {
        $destination = Join-Path $DestinationDir $item.Name
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
        [void]$restored.Add($destination)
    }
    return $restored
}

function Grant-PathAccess {
    param([string]$Path)
    $target = $Path
    if (-not (Test-Path -LiteralPath $target)) {
        $target = Split-Path -Path $Path -Parent
    }
    if (-not (Test-Path -LiteralPath $target)) {
        throw "无法定位权限目标: $Path"
    }

    $takeownArgs = @("/F", $target, "/A")
    & takeown.exe @takeownArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "takeown 执行失败: $target"
    }

    $icaclsArgs = @($target, "/grant", "*S-1-5-32-544:F", "/C")
    & icacls.exe @icaclsArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "icacls 授权失败: $target"
    }
}

function Decode-PatchText {
    param([string]$Value)
    return [System.Text.RegularExpressions.Regex]::Unescape($Value)
}

function Count-LiteralOccurrences {
    param(
        [string]$Text,
        [string]$Value
    )
    if ([string]::IsNullOrEmpty($Value)) {
        return 0
    }
    return [System.Text.RegularExpressions.Regex]::Matches(
        $Text,
        [System.Text.RegularExpressions.Regex]::Escape($Value)
    ).Count
}

function Get-AssetFiles {
    param([string]$AssetsDir)
    $files = New-Object System.Collections.ArrayList
    foreach ($pattern in @("*.js", "*.css")) {
        foreach ($file in Get-ChildItem -LiteralPath $AssetsDir -Filter $pattern -File) {
            [void]$files.Add($file)
        }
    }
    return @($files | Sort-Object FullName)
}

function Get-CompressedAssetPath {
    param([string]$AssetPath)
    return "$AssetPath.zst"
}

function Invoke-NodeInlineScript {
    param(
        [string]$ScriptContent,
        [string[]]$Arguments = @()
    )
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $node) {
        throw "未找到 node 命令。"
    }

    $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + ".cjs")
    try {
        Write-Utf8Text -Path $tempScript -Content $ScriptContent
        return & $node.Source $tempScript @Arguments
    }
    finally {
        if (Test-Path -LiteralPath $tempScript -PathType Leaf) {
            Remove-Item -LiteralPath $tempScript -Force
        }
    }
}

function Compress-FileWithZstd {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    $script = @'
const fs = require("node:fs");
const zlib = require("node:zlib");
const source = process.argv[2];
const destination = process.argv[3];
const input = fs.readFileSync(source);
const output = zlib.zstdCompressSync(input);
fs.writeFileSync(destination, output);
'@
    Invoke-NodeInlineScript -ScriptContent $script -Arguments @($SourcePath, $DestinationPath) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "zstd 压缩失败: $SourcePath"
    }
}

function Read-CompressedUtf8Text {
    param([string]$Path)
    $script = @'
const fs = require("node:fs");
const zlib = require("node:zlib");
const input = fs.readFileSync(process.argv[2]);
const output = zlib.zstdDecompressSync(input);
process.stdout.write(output);
'@
    return Invoke-NodeInlineScript -ScriptContent $script -Arguments @($Path)
}

function Expand-CompressedFile {
    param(
        [string]$CompressedPath,
        [string]$DestinationPath
    )
    $script = @'
const fs = require("node:fs");
const zlib = require("node:zlib");
const input = fs.readFileSync(process.argv[2]);
const output = zlib.zstdDecompressSync(input);
fs.writeFileSync(process.argv[3], output);
'@
    Invoke-NodeInlineScript -ScriptContent $script -Arguments @($CompressedPath, $DestinationPath) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "zstd 解压失败: $CompressedPath"
    }
}

function Get-PatchedCompressedAssetPath {
    param(
        [string]$PatchedAssetsDir,
        [string]$AssetPath
    )
    return Join-Path $PatchedAssetsDir ([System.IO.Path]::GetFileName($AssetPath) + ".zst")
}

function Get-ManagedPatchedAssets {
    param(
        [string]$PatchedAssetsDir,
        [string]$AssetsDir
    )
    $managed = New-Object System.Collections.ArrayList
    foreach ($compressed in Get-ChildItem -LiteralPath $PatchedAssetsDir -Filter "*.zst" -File | Sort-Object Name) {
        $assetName = [System.IO.Path]::GetFileNameWithoutExtension($compressed.Name)
        $assetPath = Join-Path $AssetsDir $assetName
        if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
            continue
        }

        [void]$managed.Add([pscustomobject]@{
                AssetPath      = $assetPath
                CompressedPath = $compressed.FullName
            })
    }

    return @($managed)
}

function Sync-CompressedAsset {
    param(
        [string]$SourceAssetPath,
        [string]$CompressedAssetPath,
        [string]$ProjectCompressedPath
    )
    if ($ProjectCompressedPath -and (Test-Path -LiteralPath $ProjectCompressedPath -PathType Leaf)) {
        Copy-Item -LiteralPath $ProjectCompressedPath -Destination $CompressedAssetPath -Force
        return "copied"
    }

    Compress-FileWithZstd -SourcePath $SourceAssetPath -DestinationPath $CompressedAssetPath
    return "rebuilt"
}

function Analyze-PatchHits {
    param(
        $Patches,
        $AssetFiles
    )
    $results = New-Object System.Collections.ArrayList
    foreach ($patch in $Patches) {
        $find = Decode-PatchText -Value $patch["find"]
        $replace = Decode-PatchText -Value $patch["replace"]
        $matchedFiles = New-Object System.Collections.ArrayList
        $replacedFiles = New-Object System.Collections.ArrayList
        $totalHits = 0
        $totalReplacedHits = 0

        foreach ($file in $AssetFiles) {
            $text = Read-Utf8Text -Path $file.FullName
            $hitCount = Count-LiteralOccurrences -Text $text -Value $find
            $replacedCount = Count-LiteralOccurrences -Text $text -Value $replace
            if ($hitCount -gt 0) {
                [void]$matchedFiles.Add([pscustomobject]@{
                        file  = $file.FullName
                        count = $hitCount
                    })
                $totalHits += $hitCount
            }
            if ($replacedCount -gt 0) {
                [void]$replacedFiles.Add([pscustomobject]@{
                        file  = $file.FullName
                        count = $replacedCount
                    })
                $totalReplacedHits += $replacedCount
            }
        }

        [void]$results.Add([pscustomobject]@{
                description       = $patch["description"]
                find              = $patch["find"]
                replace           = $patch["replace"]
                matched           = $totalHits -gt 0
                alreadyPatched    = $totalHits -eq 0 -and $totalReplacedHits -gt 0
                totalHits         = $totalHits
                totalReplacedHits = $totalReplacedHits
                files             = @($matchedFiles)
                replacedFiles     = @($replacedFiles)
            })
    }
    return @($results)
}

function Get-PatchTargetFiles {
    param($PatchAnalysis)
    $targets = @{}
    foreach ($result in $PatchAnalysis) {
        foreach ($fileInfo in @($result.files) + @($result.replacedFiles)) {
            $targets[$fileInfo.file] = $true
        }
    }
    return $targets.Keys
}

function Apply-PatchesToFile {
    param(
        [string]$Path,
        $Patches
    )
    $text = Read-Utf8Text -Path $Path
    $changes = New-Object System.Collections.ArrayList

    foreach ($patch in $Patches) {
        $find = Decode-PatchText -Value $patch["find"]
        $replace = Decode-PatchText -Value $patch["replace"]
        if ($find -eq $replace) {
            continue
        }

        $count = Count-LiteralOccurrences -Text $text -Value $find
        if ($count -gt 0) {
            $text = $text.Replace($find, $replace)
            [void]$changes.Add([pscustomobject]@{
                    description = $patch["description"]
                    count       = $count
                })
        }
    }

    if ($changes.Count -gt 0) {
        Write-Utf8Text -Path $Path -Content $text
    }

    return @($changes)
}

function Remove-LegacyZhCnWatermark {
    param([string]$Path)
    if ([System.IO.Path]::GetExtension($Path) -ne ".css") {
        return $false
    }

    $text = Read-Utf8Text -Path $Path
    $pattern = 'html\[lang=zh-CN\] body::after\{content:"[^"]*";position:fixed;right:max\(14px,env\(safe-area-inset-right\)\);bottom:max\(10px,env\(safe-area-inset-bottom\)\);font:500 11px/1 var\(--font-ui\);color:var\(--text-500,#8a8a8a\);opacity:\.32;letter-spacing:\.02em;pointer-events:none;user-select:none;z-index:2147483000\}'
    $cleaned = [System.Text.RegularExpressions.Regex]::Replace($text, $pattern, "")

    if ($cleaned -cne $text) {
        Write-Utf8Text -Path $Path -Content $cleaned
        return $true
    }

    return $false
}

function Normalize-LegacyZhCnLanguageLabel {
    param([string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -notin @(".js", ".css")) {
        return $false
    }

    $text = Read-Utf8Text -Path $Path
    $patterns = @(
        "简体中文（by芹菜香）",
        "简体中文（By芹菜香）",
        "简体中文(by芹菜香)",
        "简体中文(By芹菜香)"
    )

    $cleaned = $text
    foreach ($pattern in $patterns) {
        $cleaned = $cleaned.Replace($pattern, "简体中文")
    }

    if ($cleaned -cne $text) {
        Write-Utf8Text -Path $Path -Content $cleaned
        return $true
    }

    return $false
}

function Compare-TextFiles {
    param(
        [string]$Left,
        [string]$Right
    )
    return (Read-Utf8Text -Path $Left) -ceq (Read-Utf8Text -Path $Right)
}

function Compare-BinaryFiles {
    param(
        [string]$Left,
        [string]$Right
    )
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Left).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $Right).Hash
}

function Compare-CompressedFileToSource {
    param(
        [string]$SourcePath,
        [string]$CompressedPath
    )
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $CompressedPath -PathType Leaf)) {
        return $false
    }
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    try {
        Expand-CompressedFile -CompressedPath $CompressedPath -DestinationPath $tempPath
        return Compare-BinaryFiles -Left $SourcePath -Right $tempPath
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Add-VerificationMapIssues {
    param(
        $Issues,
        $ExpectedMap,
        $ActualMap,
        [string]$Description
    )
    foreach ($key in $ExpectedMap.Keys) {
        if (-not $ActualMap.ContainsKey($key)) {
            [void]$Issues.Add("$Description 缺少关键键值: $key")
            continue
        }
        if ($ActualMap[$key] -ne $ExpectedMap[$key]) {
            [void]$Issues.Add("$Description 键值不匹配: $key")
        }
    }
}

function Test-TextFileMatches {
    param(
        [string]$ExpectedPath,
        [string]$ActualPath
    )
    if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $ActualPath -PathType Leaf)) {
        return $false
    }

    return Compare-TextFiles -Left $ExpectedPath -Right $ActualPath
}

function Test-BinaryFileMatches {
    param(
        [string]$ExpectedPath,
        [string]$ActualPath
    )
    if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $ActualPath -PathType Leaf)) {
        return $false
    }

    return Compare-BinaryFiles -Left $ExpectedPath -Right $ActualPath
}

function Get-VerificationIssues {
    param($Config)
    $artifacts = Get-ProjectArtifacts
    Assert-SupportedInstallation -Config $Config
    Assert-ProjectArtifacts -Artifacts $artifacts

    $issues = New-Object System.Collections.ArrayList
    $targets = Get-VerificationTargets
    $applyTargets = $Config["applyTargets"]

    if (-not (Test-TextFileMatches -ExpectedPath $artifacts["RootLocale"] -ActualPath $applyTargets["rootLocale"])) {
        [void]$issues.Add("root zh-CN.json 未与项目副本同步")
    }
    if (-not (Test-TextFileMatches -ExpectedPath $artifacts["IonLocale"] -ActualPath $applyTargets["ionLocale"])) {
        [void]$issues.Add("ion zh-CN.json 未与项目副本同步")
    }
    if (-not (Test-BinaryFileMatches -ExpectedPath $artifacts["IonLocaleZst"] -ActualPath $applyTargets["ionLocaleZst"])) {
        [void]$issues.Add("ion zh-CN.json.zst 未与项目副本同步")
    }
    if (-not (Test-TextFileMatches -ExpectedPath $artifacts["IonOverrides"] -ActualPath $applyTargets["ionOverrides"])) {
        [void]$issues.Add("ion zh-CN.overrides.json 未与项目副本同步")
    }
    if (-not (Test-BinaryFileMatches -ExpectedPath $artifacts["IonOverridesZst"] -ActualPath $applyTargets["ionOverridesZst"])) {
        [void]$issues.Add("ion zh-CN.overrides.json.zst 未与项目副本同步")
    }
    if (-not (Test-TextFileMatches -ExpectedPath $artifacts["StatsigLocale"] -ActualPath $applyTargets["statsigLocale"])) {
        [void]$issues.Add("statsig zh-CN.json 未与项目副本同步")
    }
    if (-not (Test-BinaryFileMatches -ExpectedPath $artifacts["StatsigLocaleZst"] -ActualPath $applyTargets["statsigLocaleZst"])) {
        [void]$issues.Add("statsig zh-CN.json.zst 未与项目副本同步")
    }

    if (Test-Path -LiteralPath $applyTargets["rootLocale"] -PathType Leaf) {
        $rootMap = Read-JsonObject -Path $applyTargets["rootLocale"]
        Add-VerificationMapIssues -Issues $issues -ExpectedMap $targets["rootLocale"] -ActualMap $rootMap -Description "root zh-CN"
    }
    if (Test-Path -LiteralPath $applyTargets["ionLocale"] -PathType Leaf) {
        $ionMap = Read-JsonObject -Path $applyTargets["ionLocale"]
        Add-VerificationMapIssues -Issues $issues -ExpectedMap $targets["ionLocale"] -ActualMap $ionMap -Description "ion zh-CN"
    }
    if (Test-Path -LiteralPath $applyTargets["statsigLocale"] -PathType Leaf) {
        $statsigMap = Read-JsonObject -Path $applyTargets["statsigLocale"]
        Add-VerificationMapIssues -Issues $issues -ExpectedMap $targets["statsigLocale"] -ActualMap $statsigMap -Description "statsig zh-CN"
    }

    $patches = Get-Patches
    $assetFiles = Get-AssetFiles -AssetsDir $applyTargets["assetsDir"]
    $patchAnalysis = Analyze-PatchHits -Patches $patches -AssetFiles $assetFiles

    foreach ($file in $assetFiles) {
        $text = Read-Utf8Text -Path $file.FullName
        if ($text.Contains("简体中文（by芹菜香）") -or $text.Contains("简体中文（By芹菜香）") -or $text.Contains("简体中文(by芹菜香)") -or $text.Contains("简体中文(By芹菜香)")) {
            [void]$issues.Add("仍有旧版语言菜单署名残留: $($file.Name)")
        }
        foreach ($patch in $patches) {
            $find = Decode-PatchText -Value $patch["find"]
            $replace = Decode-PatchText -Value $patch["replace"]
            $findCount = Count-LiteralOccurrences -Text $text -Value $find
            if ($findCount -le 0) {
                continue
            }

            $replaceCount = Count-LiteralOccurrences -Text $text -Value $replace
            if ($replaceCount -gt 0 -and $replaceCount -ge $findCount) {
                continue
            }

            if ($findCount -gt 0) {
                [void]$issues.Add("仍有英文回退残留: $($patch['description']) -> $($file.Name)")
            }
        }
    }

    $managedAssets = Get-ManagedPatchedAssets -PatchedAssetsDir $artifacts["PatchedAssetsDir"] -AssetsDir $applyTargets["assetsDir"]
    $patchTargets = @(Get-PatchTargetFiles -PatchAnalysis $patchAnalysis)
    $patchTargets = @($patchTargets + @($managedAssets | ForEach-Object { $_.AssetPath }) | Sort-Object -Unique)
    foreach ($assetPath in $patchTargets) {
        $installedCompressed = Get-CompressedAssetPath -AssetPath $assetPath
        if (-not (Compare-CompressedFileToSource -SourcePath $assetPath -CompressedPath $installedCompressed)) {
            [void]$issues.Add("压缩 bundle 未与当前明文资源同步: $([System.IO.Path]::GetFileName($installedCompressed))")
        }
    }

    return $issues
}
