import 'package:test/test.dart';
import 'package:toolbox_service/src/ops/appbackup.dart';

/// 对应 TS 版 src/main/ops/install.ts 的 pickSplits（.apks 备份恢复时用它挑分包）
void main() {
  test('pickSplits 只留手机最优先支持的 ABI，其余分包全装', () {
    final names = [
      'base.apk',
      'split_config.arm64_v8a.apk',
      'split_config.armeabi_v7a.apk',
      'split_config.zh.apk',
      'split_config.xxhdpi.apk',
      'standalones/standalone-arm64_v8a.apk',
      'instant/base.apk',
      'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb',
    ];
    expect(pickSplits(names, 'arm64-v8a,armeabi-v7a,armeabi'), [
      'base.apk',
      'split_config.arm64_v8a.apk',
      'split_config.zh.apk',
      'split_config.xxhdpi.apk',
    ]);
    expect(pickSplits(names, 'armeabi-v7a,arm64-v8a'), [
      'base.apk',
      'split_config.armeabi_v7a.apk',
      'split_config.zh.apk',
      'split_config.xxhdpi.apk',
    ]);
  });

  test('pickSplits 读不到 ABI 列表时只装没有 ABI 的分包', () {
    expect(
      pickSplits(['base.apk', 'split_config.arm64_v8a.apk', 'split_config.en.apk'], ''),
      ['base.apk', 'split_config.en.apk'],
    );
  });

  test('pickSplits 没有 APK 时返回空', () {
    expect(pickSplits(['BUNDLE-METADATA/x.pb'], 'arm64-v8a'), isEmpty);
  });
}
