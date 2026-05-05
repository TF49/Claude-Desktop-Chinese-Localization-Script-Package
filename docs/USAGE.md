# 使用说明

## 适用范围

- 支持兼容资源结构的 Claude Desktop 安装
- 自动识别兼容安装目录，优先检查：
  - `C:\Program Files\WindowsApps\Claude_*_x64__pzs8sxrjxfjjc\app\resources`
  - `%LOCALAPPDATA%\AnthropicClaude\app-*\resources`
- 不需要安装 Python
- 会自动请求管理员权限

## 下载建议

- 普通用户优先在 GitHub 仓库页面点击 `Code -> Download ZIP`
- 也可以用 README 里的 PowerShell 快速下载命令
- 解压位置建议放在桌面或其他普通目录，不要放进 `WindowsApps`

## 三个入口

- `一键应用.bat`
  - 自动执行：备份 -> 应用 -> 自动校验
- `一键校验.bat`
  - 只检查当前安装目录里的汉化状态
- `一键回滚.bat`
  - 恢复到最近一次成功应用前的备份

## 推荐流程

1. 先完全退出 Claude Desktop
2. 双击 `一键应用.bat`
3. 看到自动校验通过后，再打开 Claude Desktop
4. 如果怀疑某次升级覆盖了资源，再运行 `一键校验.bat`
5. 如果当前效果不符合预期，再运行 `一键回滚.bat`

## 脚本会做什么

`一键应用.bat` 会：

1. 请求管理员权限
2. 检查目标安装目录和关键资源结构是否存在
3. 备份当前 `zh-CN` 资源和命中的 js 文件
4. 复制项目中的 `zh-CN` json / `.zst` 资源
5. 应用运行时 patch
6. 自动执行校验

## 备份目录

每次成功进入应用流程后，都会在项目根目录的 `backups/时间戳/` 下生成备份。

其中通常会包含：

- `root/`
- `ion/`
- `ion-overrides/`
- `statsig/`
- `assets/`
- `apply-report.json`

## 常见失败原因

- 资源结构不兼容
  - 当前按安装目录和关键资源结构自动识别；如果新版目录结构变化，脚本仍会拒绝继续
- 安装目录不对
  - 当前只识别兼容的 `WindowsApps` 或官网安装目录
- 权限不足
  - 请确认管理员授权弹窗没有被拒绝
- 系统策略阻止修改 `WindowsApps`
  - 这种情况即使管理员权限也可能失败

## 反馈时请带什么

如果你准备在 GitHub 提 issue，最好附上这些信息：

- Claude Desktop 版本号
- `一键校验.bat` 的完整输出
- 仍然显示英文的页面截图
- 你当前实际命中的安装目录
