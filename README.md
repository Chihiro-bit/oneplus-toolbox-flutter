# 一加工具箱 · Flutter 版

[oneplus-toolbox](../oneplus-toolbox)（Electron / TypeScript 版）的 Flutter 移植，功能一致。本仓库独立于 TS 版，用 [melos](https://melos.invertase.dev) 管理的多包工作区，按职责分成四层：

```
apps/oneplus_toolbox        UI：页面、组件、交互状态（Flutter）
     │  只依赖 toolbox_service
     ▼
packages/toolbox_service    业务：设备轮询、各项操作的流程编排与安全检查、方案目录、设置、更新检查
     │                      对外只暴露 ToolboxService 一个入口
     ▼
packages/toolbox_commands   命令：adb / fastboot / payload_dumper / 7-Zip、校验下载、手机端脚本
     │                      只负责「怎么执行、怎么解析输出」，不做业务判断
     ▼
packages/toolbox_core       共享模型、内置方案目录、校验规则、取消令牌（纯 Dart，无 IO）
```

依赖只能向下，`melos run check:layers` 会检查每个包的 pubspec 依赖和 `package:` 导入（例如界面直接 import `toolbox_commands` 会报错）。除界面外的三层都是纯 Dart 包，可以单独用 `dart test` 测试。

## 与 TS 版的对应关系

| TS 版 | Flutter 版 |
| --- | --- |
| `src/shared/types.ts`、`catalog.ts` | `toolbox_core` |
| `src/main/exec.ts`、`download.ts`、`ops/patch-script.ts` 及各命令调用 | `toolbox_commands` |
| `src/main/index.ts`（IPC）、`device.ts`、`ops/*`、`catalog.ts`、`settings.ts`、`update.ts` | `toolbox_service`（`ToolboxService` 取代 IPC） |
| `src/renderer` | `apps/oneplus_toolbox` |
| `scripts/fetch-tools.mjs` | `tool/fetch_tools.dart` |

- 发到手机上的脚本与 TS 版逐字一致，由 `toolbox_commands/test/golden/` 中的快照测试保证（快照由 TS 版生成，TS 版修改脚本后需同步更新）
- 设置、方案目录缓存和 APK 缓存与 Electron 版共用 `%APPDATA%\一加工具箱`
- 修补后的镜像同样保存到「文档\一加工具箱」

## 开发

前置条件：

- Flutter 3.22+（Dart 3.4+），`dart pub global activate melos`
- 构建 Windows 版需要 Visual Studio（「使用 C++ 的桌面开发」工作负载），并在系统设置中开启**开发者模式**（插件需要符号链接）
- 第三方工具（adb、fastboot、payload_dumper、7za、aapt2、Magisk）不提交到仓库：运行 `melos run fetch-tools` 从官方地址下载并校验 sha256，放到 `resources/bin`；构建时 CMake 会把它复制到 exe 旁边的 `bin/`。版本与 TS 版的 `scripts/fetch-tools.mjs` 一致

```bash
melos bootstrap
melos run fetch-tools    # 首次运行，或升级工具版本后
melos run analyze        # 静态检查
melos run test           # 全部测试
melos run check:layers   # 分层检查
melos run format         # 格式化（120 列）
melos exec --scope=oneplus_toolbox -- flutter run -d windows
melos run build:windows  # 发布版，输出在 apps/oneplus_toolbox/build/windows/x64/runner/Release
```

构建时可用 `--dart-define=TOOLBOX_VERSION=x.y.z` 和 `--dart-define=TOOLBOX_UPDATE_REPO=owner/repo` 指定版本号和默认更新仓库（对应 TS 版的 `TOOLBOX_UPDATE_REPO` 环境变量）。

## 许可证

Apache License 2.0，见 [LICENSE](LICENSE)。随程序分发的第三方组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
