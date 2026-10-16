/// 「备份关键分区」里发到手机上的脚本与备份目录里 SHA256SUMS.txt 的生成规则。
///
/// 对应 TS 版的 src/main/ops/backup.ts 与 src/main/ops/root.ts 里的 dd / pull 流程。
/// 这里的字符串必须与 TS 版逐字一致。
library;

import 'package:toolbox_core/toolbox_core.dart';

import 'patch_script.dart';

/// 基带、校准数据所在的分区：坏了刷什么 ROM 都恢复不了（IMEI 丢失、没信号、传感器失灵），只能靠自己的备份。
/// 这些分区不随 ROM 提供，每台手机都不一样。
const uniquePartitions = ['persist', 'modemst1', 'modemst2', 'fsg', 'fsc', 'ocdt'];

/// 当前槽位的启动相关分区（这些 ROM 里有，备份是为了以后刷回「当时的样子」）
const slotPartitions = ['boot', 'init_boot', 'vendor_boot', 'dtbo'];

/// 从 ROM 里提取并保存的原厂镜像
const romPartitions = [
  StockPartition.initBoot,
  StockPartition.boot,
  StockPartition.vendorBoot,
  StockPartition.dtbo,
  StockPartition.vbmeta,
  StockPartition.vbmetaSystem,
  StockPartition.vbmetaVendor,
];

/// 手机上接收备份的临时目录（对应 TS 的 `${REMOTE_DIR}/backup`）
String get backupRemote => '$remoteDir/backup';

/// 拿 Root 权限：输出最后一行是 `0` 表示已授权
const suIdCommand = "timeout 30 su -c 'id -u' 2>&1";

/// 列出手机上实际存在的分区（不同机型不全有），输出形如 `HAS|persist`
String listPartitionsCommand(List<String> wanted) =>
    "su -c 'for p in ${wanted.join(' ')}; do [ -e /dev/block/by-name/\$p ] && echo \"HAS|\$p\"; done'";

final _presentLine = RegExp(r'^HAS\|(\S+)', multiLine: true);

/// 解析「手机上实际存在哪些分区」的输出
List<String> parsePresentPartitions(String out) => [
      for (final m in _presentLine.allMatches(out)) m[1]!,
    ];

/// 重建手机上的临时目录：`rm -rf <remote> && mkdir -p <remote>`
String resetRemoteCommand(String remote) => 'rm -rf $remote && mkdir -p $remote';

/// 用 root 的 dd 从分区读出镜像，并改成所有人可读 —— adb pull 是 shell 身份，否则拉不下来
String ddCommand(String remote, String partition) =>
    "su -c 'dd if=/dev/block/by-name/$partition of=$remote/$partition.img bs=1048576 2>&1 && chmod 644 $remote/$partition.img'";

/// 拉回电脑后删掉手机上的临时镜像
String removeRemoteImageCommand(String remote, String partition) => 'rm -f $remote/$partition.img';

/// 备份结束（或中途失败）后删掉手机上的临时目录
String removeRemoteDirCommand(String remote) => 'rm -rf $remote';

/// SHA256SUMS.txt 的内容：第一行是手机型号和构建号，之后每个分区一行，末尾留一个空行
String sha256Sums({required String header, required List<String> lines}) => [header, ...lines, ''].join('\n');

/// 清单里的一行：`<sha256>  <文件名>  <字节数>`（两空格分隔，与 sha256sum 的输出一致）
String manifestLine(String sha256, String name, int size) => '$sha256  $name  $size';

/// 备份目录名里的时间戳，形如 `20261015123045`。
/// 与 TS 的 `new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)` 一致，用的是 UTC。
String backupStamp([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().toIso8601String().replaceAll(RegExp('[-:T]'), '').substring(0, 14);
