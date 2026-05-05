# claude-desktop win版汉化补丁

这是一个面向 `Claude Desktop WindowsApps / 官网安装目录兼容资源结构` 的汉化补丁。支持自动识别兼容安装目录，普通用户只需要：下载、解压、双击、完成。

## 三步使用教程

1. 打开 GitHub 仓库页面，点击 `Code -> Download ZIP`
2. 解压到任意普通目录
3. 双击 `一键应用.bat`

应用完成后，重新打开 Claude Desktop 检查效果。

需要复检时运行 `一键校验.bat`，需要撤销时运行 `一键回滚.bat`。

## 下载和准备

- 推荐直接在仓库页面点击 `Code -> Download ZIP`
- 如果你熟悉 PowerShell，也可以用下方命令自动下载
- 补丁包可解压到任意普通目录使用
- 不需要安装 Python
- 不要在 zip 预览里直接运行，先完整解压
- 不要只单独拿出 `一键应用.bat`，要保留完整文件结构

下载后会看到这三个主入口：

- `一键应用.bat`
- `一键校验.bat`
- `一键回滚.bat`

## PowerShell 快速下载

如果你不想手动点网页，可以在 PowerShell 里执行下面这段命令。

把 `<你的用户名>` 和 `<仓库名>` 替换成你自己的 GitHub 仓库地址后再运行：

```powershell
$repo = "https://github.com/<你的用户名>/<仓库名>/archive/refs/heads/main.zip"
$zip = Join-Path $env:TEMP "claude-desktop-zh.zip"
$desktop = [Environment]::GetFolderPath("Desktop")
$extractRoot = Join-Path $desktop "ClaudeDesktopZH"

if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}

Invoke-WebRequest -Uri $repo -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $extractRoot -Force

$projectDir = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
Start-Process -FilePath (Join-Path $projectDir.FullName "一键应用.bat")
```

这段命令会：

1. 从 GitHub 下载当前仓库的 zip
2. 解压到桌面的 `ClaudeDesktopZH`
3. 自动启动 `一键应用.bat`

## 常见问题

**需要管理员权限吗？**  
需要。运行 `一键应用.bat`、`一键校验.bat`、`一键回滚.bat` 时会请求管理员权限，这是正常现象，因为脚本需要写入 Claude Desktop 的安装资源目录。

**补丁包必须放到固定目录吗？**  
不需要。补丁包自己放哪都可以，只要是普通目录即可，比如桌面、下载、D 盘目录。固定的是 Claude Desktop 的安装目录，不是补丁包目录。

**为什么会失败？**  
最常见的原因是版本不对、Claude 没完全退出、系统策略阻止写入安装目录、或者当前资源结构和补丁预期不一致。

**支持哪些版本？**  
当前按安装目录和关键资源结构自动识别，不再写死某一个 Claude Desktop 版本号。

更细的操作说明见 [docs/USAGE.md](docs/USAGE.md)。

## 支持范围

- 支持兼容资源结构的 Claude Desktop 安装
- 支持兼容的 `WindowsApps` 安装结构
- 支持官网 `Claude Setup.exe` 安装后可识别的兼容目录
- 默认流程是：备份 -> 应用 -> 自动校验
- 提供独立回滚入口

自动识别顺序：

1. `C:\Program Files\WindowsApps\Claude_*_x64__pzs8sxrjxfjjc\app\resources`
2. `%LOCALAPPDATA%\AnthropicClaude\app-*\resources`

## 补丁内容

- 完整的 `zh-CN` 语言资源
- 对应的 `.zst` 压缩资源
- 前端运行时补丁
- 自动备份与自动校验流程

兼容入口也保留着：

- `apply.bat`
- `verify.bat`
- `rollback.bat`
- `start.bat`

## 风险和边界

- 这个补丁依赖 Claude Desktop 当前版本的实际资源结构
- 需要管理员授权；如果系统策略锁死安装目录，仍可能失败
- 只保证最近一次备份可回滚
- 如果新版 Claude Desktop 改动了资源结构，仍可能需要更新补丁
- 部分深层功能或新功能页仍可能存在少量英文残留
