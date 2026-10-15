# 第三方组件声明

本项目自身的代码以 [Apache License 2.0](LICENSE) 发布。安装包中还包含、或者运行时会下载下列第三方组件，它们各自遵循自己的许可证。

## 随安装包分发

以下文件位于程序目录的 `bin` 下，构建前由 `tool/fetch_tools.dart`（`melos run fetch-tools`）从官方地址下载并校验 sha256。

| 组件 | 版本 | 用途 | 许可证 | 源码 / 来源 |
|---|---|---|---|---|
| Android SDK Platform-Tools（adb、fastboot、AdbWinApi.dll、AdbWinUsbApi.dll） | r37.0.1 | 与手机通信、刷写分区 | Apache-2.0 等，详见随附的 `platform-tools/NOTICE.txt` | <https://developer.android.com/tools/releases/platform-tools> |
| payload-dumper-rust | 0.8.4 | 读取 OTA 包元数据、提取 boot / init_boot（支持 URL） | Apache-2.0 | <https://github.com/rhythmcache/payload-dumper-rust> |
| 7-Zip（7za.exe，经由 npm 包 7zip-bin） | 21.07 | 从线刷包中提取镜像 | GNU LGPL-2.1（含 unRAR 限制条款） | <https://www.7-zip.org/>、<https://github.com/develar/7zip-bin> |
| aapt2（Android arm64 构建） | ReVanced/aapt2 v1.1.0 | 推送到手机上读取应用名称和图标 | AOSP 源码为 Apache-2.0；构建脚本为 GPL-3.0 | <https://github.com/ReVanced/aapt2>、<https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/tools/aapt2/> |
| qdl（qdl.exe 及其自带的 libusb / libxml2 / libzip 等运行库 DLL） | 2.8 | 与处于 9008（EDL）模式的设备通信、刷写分区 | BSD-3-Clause，许可证全文随附在 `qdl/LICENSE` | <https://github.com/linux-msm/qdl> |
| Magisk（APK） | 30.7 | 离线 Root 方案 | GPL-3.0 | <https://github.com/topjohnwu/Magisk> |

## 运行时按需下载（不随安装包分发）

用户在「一键 Root」中选择对应方案时，程序才会从该项目的 GitHub Releases 下载 APK，并强制校验 sha256。

| 组件 | 许可证 | 源码 |
|---|---|---|
| Magisk | GPL-3.0 | <https://github.com/topjohnwu/Magisk> |
| APatch | GPL-3.0 | <https://github.com/bmax121/APatch> |
| KernelSU | GPL-3.0 | <https://github.com/tiann/KernelSU> |
| KernelSU Next | GPL-3.0 | <https://github.com/KernelSU-Next/KernelSU-Next> |
| SukiSU Ultra | GPL-3.0 | <https://github.com/SukiSU-Ultra/SukiSU-Ultra> |

## 打包进程序本体的库

| 组件 | 许可证 |
|---|---|
| Flutter 引擎与框架（含 Skia、ICU 等） | BSD-3-Clause 等，各组件的声明见程序目录 `data/flutter_assets/NOTICES.Z` |
| file_selector、path_provider、url_launcher 及其 Windows 实现 | BSD-3-Clause |
| Dart 包 path、crypto | BSD-3-Clause |

这些组件的版权归各自作者所有。本项目与上述任何项目、Google、OnePlus 均无隶属或背书关系。
