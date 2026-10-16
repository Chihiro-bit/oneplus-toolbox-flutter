import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';
import 'rescue.dart';
import 'root.dart';

/// 备份关键分区与从 ROM 保存原厂镜像。对应 TS 版的 src/main/ops/backup.ts。
Future<OperationResult> backupPartitions(BackupOptions opts, OpContext ctx) =>
    opts.source == BackupSource.device ? _backupFromDevice(ctx) : _backupFromRom(opts.rom ?? '', ctx);

/// 已 Root：在手机上用 dd 读出分区，拉回电脑，逐个记下 sha256。只读，不写手机上的任何分区
Future<OperationResult> _backupFromDevice(OpContext ctx) async {
  final serial = await ctx.requireSystem();
  final props = await ctx.probe.getProps(serial, ctx.cancel);
  // 要拼进 shell 命令，只接受 _a / _b
  final suffix = props['ro.boot.slot_suffix'] ?? '';
  final slot = RegExp(r'^_[ab]$').hasMatch(suffix) ? suffix : '';

  ctx.step('正在获取 Root 权限，手机上弹出授权时请点允许');
  final id = await ctx.adb.shell(serial, [suIdCommand], timeout: const Duration(seconds: 45));
  if (id.stdout.trim().split(RegExp(r'\r?\n')).last != '0') {
    throw const OpException('没有拿到 Root 权限。没 Root 的手机可以改用「从 ROM 提取原厂镜像」；已 Root 的请在管理器里允许 Shell 的超级用户权限');
  }

  // 先列出手机上实际存在的分区，不同机型不全有
  final wanted = [...uniquePartitions, for (final x in slotPartitions) '$x$slot'];
  final ls = await ctx.adb.shell(
    serial,
    [listPartitionsCommand(wanted)],
    timeout: const Duration(seconds: 30),
    echoOutput: false,
  );
  final present = parsePresentPartitions(ls.stdout);
  if (present.isEmpty) throw const OpException('在 /dev/block/by-name 下没找到要备份的分区');
  final skipped = [
    for (final x in wanted)
      if (!present.contains(x)) x
  ];
  if (skipped.isNotEmpty) ctx.log(LogLevel.info, '这台手机没有：${skipped.join('、')}');

  final dir = p.join(
    ctx.history.backupDir(serial, props['ro.build.date.utc']),
    'partitions_${backupStamp()}',
  );
  Directory(dir).createSync(recursive: true);
  final remote = backupRemote;
  await ctx.adb.shell(serial, [resetRemoteCommand(remote)]);
  final manifest = <String>[];
  try {
    for (final part in present) {
      ctx.step('正在备份 $part');
      // dd 由 root 写出，改成所有人可读，adb pull（shell 身份）才拉得下来
      final r = await ctx.adb.shell(serial, [ddCommand(remote, part)], timeout: const Duration(minutes: 10));
      if (!r.ok) throw OpException('读取 $part 失败，详见日志');
      final local = p.join(dir, '$part.img');
      final pull = await ctx.adb.pull(serial, '$remote/$part.img', local, timeout: const Duration(minutes: 10));
      if (!pull.ok || !File(local).existsSync()) throw OpException('从手机取回 $part 失败');
      await ctx.adb.shell(serial, [removeRemoteImageCommand(remote, part)]);
      manifest.add(manifestLine(await sha256File(local), '$part.img', File(local).lengthSync()));
    }
  } finally {
    try {
      await ctx.adb.shell(serial, [removeRemoteDirCommand(remote)]);
    } catch (_) {
      // 手机可能已经断开，尽力清理
    }
  }
  final header = '# ${props['ro.product.model'] ?? ''} ${props['ro.build.display.id'] ?? ''}  '
      '${formatDateTime(DateTime.now().millisecondsSinceEpoch)}';
  final sums = p.join(dir, 'SHA256SUMS.txt');
  File(sums).writeAsStringSync(sha256Sums(header: header, lines: manifest));
  return OperationResult(
    ok: true,
    message: '已备份 ${present.length} 个分区。persist、modemst 等是这台手机独有的数据，请另外复制一份到网盘或其它电脑',
    outputPath: sums,
  );
}

/// 没 Root：从和手机版本一致的 ROM 里提取原厂启动镜像，存进备份目录，卡开机时可以直接用
Future<OperationResult> _backupFromRom(String rom, OpContext ctx) async {
  if (rom.trim().isEmpty) throw const OpException('请先选择 ROM');
  final serial = await ctx.requireSystem();
  final props = await ctx.probe.getProps(serial, ctx.cancel);
  final dir = workDir(ctx.env);
  await extractImages(
    rom.trim(),
    props['ro.build.date.utc'],
    dir,
    ctx,
    partitions: [for (final x in romPartitions) x.id],
  );
  final saved = <String>[];
  var last = '';
  for (final part in romPartitions) {
    final img = findFile(dir, '${part.id}.img');
    if (img == null) continue;
    last = (await ctx.history.backupImage(serial, props['ro.build.date.utc'], part.id, img)).path;
    saved.add(part.id);
  }
  if (saved.isEmpty) throw const OpException('没能从 ROM 中提取出任何镜像');
  return OperationResult(
    ok: true,
    message: '已保存原厂 ${saved.join('、')}（${p.basename(p.dirname(last))}）',
    outputPath: last,
  );
}
