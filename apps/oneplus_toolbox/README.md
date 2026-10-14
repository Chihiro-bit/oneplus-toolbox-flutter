# oneplus_toolbox

一加工具箱 Flutter 版的界面层。只依赖 `toolbox_service`，通过 `ToolboxService` 执行操作、订阅设备状态和日志。

- `lib/main.dart`：入口，解析运行环境并创建 `ToolboxService`
- `lib/src/controller.dart`：把服务的各个流转成界面状态（对应 TS 版 `state.ts`）
- `lib/src/pages/`：各功能页面
- `lib/src/widgets/`：运行状态横幅、确认对话框、非一加设备警告、日志面板等公共组件

开发与构建说明见上级目录的 [README](../../README.md)。
