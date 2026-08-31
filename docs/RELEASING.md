# XmaxSDK HarmonyOS 发版指南

本文档用于发布 XmaxSDK HarmonyOS 的新版本。发版产物为源码 HAR，HAR 仅上传至 GitHub Release，不提交到 Git 仓库。

## 发版前准备

- 确认当前分支包含准备发布的全部代码，且没有无关的本地修改。
- 使用 DevEco Studio 配套的 Node.js 和 Hvigor 构建，避免系统 Node.js 版本与 Hvigor 不兼容。
- 确认项目依赖已经安装，并已按照 README 手动配置本地 VolcEngine RTC SDK。
- 确认准备发布的版本号，例如 `1.0.2`。

## 1. 更新版本号

以下文件中的版本号必须保持一致：

- `xmax_sdk/oh-package.json5` 中的 `version`
- `xmax_sdk/Index.ets` 中的 `XMAX_SDK_VERSION`
- `xmax_sdk/BuildProfile.ets` 中的 `HAR_VERSION`
- `xmax_sdk/src/main/cpp/types/libxmax_video/oh-package.json5` 中的 `version`

同时更新根目录 `README.md` 中的以下内容：

- GitHub Release 下载链接中的版本号
- HAR 文件名，例如 `xmaxsdk-1.0.2.har`
- 手动安装示例中的本地 HAR 路径

更新完成后，检查版本号是否一致：

```shell
rg -n 'version|XMAX_SDK_VERSION|HAR_VERSION|xmaxsdk-' \
  README.md \
  xmax_sdk/oh-package.json5 \
  xmax_sdk/Index.ets \
  xmax_sdk/BuildProfile.ets \
  xmax_sdk/src/main/cpp/types/libxmax_video/oh-package.json5
```

## 2. 清理不应进入产物的文件

检查 SDK 源码目录中是否存在 macOS 生成的 `.DS_Store`：

```shell
find xmax_sdk -name .DS_Store -not -path '*/build/*'
```

如果命令有输出，删除对应文件后再构建。不要将 VolcEngine RTC HAR 或其他无再分发授权的二进制打包进 XmaxSDK HAR。

## 3. 构建 Release HAR

在仓库根目录执行：

```shell
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
--mode module \
-p module=xmax_sdk@default \
-p product=default \
-p buildMode=release \
assembleHar \
--no-daemon
```

构建成功后，原始产物位于：

```text
xmax_sdk/build/default/outputs/default/xmax_sdk.har
```

## 4. 生成带版本号的发布文件

将下面的版本号替换为本次发布版本：

```shell
SDK_RELEASE_VERSION=1.0.2
cp "xmax_sdk/build/default/outputs/default/xmax_sdk.har" \
  "xmax_sdk/build/default/outputs/default/xmaxsdk-${SDK_RELEASE_VERSION}.har"
```

最终上传文件位于：

```text
xmax_sdk/build/default/outputs/default/xmaxsdk-<version>.har
```

## 5. 校验发布产物

HarmonyOS HAR 是 gzip 压缩的 tar 包，检查内容时使用 `tar`，不要使用 `unzip`。

```shell
SDK_RELEASE_VERSION=1.0.2
SDK_RELEASE_HAR="xmax_sdk/build/default/outputs/default/xmaxsdk-${SDK_RELEASE_VERSION}.har"

tar -xOzf "$SDK_RELEASE_HAR" package/oh-package.json5
tar -xOzf "$SDK_RELEASE_HAR" package/BuildProfile.ets
tar -xOzf "$SDK_RELEASE_HAR" package/Index.ets | rg XMAX_SDK_VERSION
tar -tzf "$SDK_RELEASE_HAR" | rg '\.DS_Store|volcenginertc|libRealX|libbyte'
shasum -a 256 "$SDK_RELEASE_HAR"
```

校验结果应满足：

- 包版本、`HAR_VERSION` 和 `XMAX_SDK_VERSION` 均为本次发布版本。
- `artifactType` 为 `original`。
- `BUILD_MODE_NAME` 为 `release`，`DEBUG` 为 `false`。
- 敏感文件检查命令没有任何输出。
- 产物中不包含 VolcEngine RTC HAR 或其二进制文件。
- 记录 SHA-256，必要时随 Release Notes 一起发布。

构建日志必须以 `BUILD SUCCESSFUL` 结束。已有三方依赖警告可以记录，但出现新的警告时仍需确认不会影响发布。

## 6. 提交代码并创建 Release

1. 使用 `git status` 和 `git diff` 检查版本号、README 与本次代码变更。
2. 提交源码和文档，不要执行 `git add -f` 强制提交 HAR。
3. 将发布提交合并到 `main`，并确保远端 `main` 已更新。
4. 在发布提交上创建与版本号一致的 Git Tag，例如 `1.0.2`。
5. 推送 Tag，在 GitHub 中基于该 Tag 创建 Release。
6. 手动上传 `xmaxsdk-<version>.har`，并确认 README 下载链接与 Tag、文件名完全一致。

## Git 忽略规则

根目录 `.gitignore` 已包含：

```gitignore
**/build/
*.har
xmax_sdk/libs/
```

因此构建产物、发布 HAR 和本地 RTC HAR 默认不会进入版本控制。若 `git status` 中出现任何 HAR，应先检查文件位置和忽略规则，不要直接提交。

## 发版检查清单

- [ ] 四处 SDK 版本号保持一致
- [ ] README 下载链接、文件名和安装示例已更新
- [ ] Release 构建成功
- [ ] 产物为源码 HAR，且 `DEBUG` 为 `false`
- [ ] 产物不包含 `.DS_Store` 或 VolcEngine RTC 二进制
- [ ] SHA-256 已生成并记录
- [ ] Git 工作区中没有误提交的 HAR
- [ ] `main`、Git Tag、GitHub Release 指向同一发布提交
- [ ] GitHub Release 已上传正确版本的 HAR
