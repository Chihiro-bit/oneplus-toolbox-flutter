/// 联网检测（captive portal）和私人 DNS 用到的 settings 键。
///
/// 原生 Android 默认访问 Google 的 generate_204 判断能不能上网，国内访问不到，Wi-Fi 就会显示感叹号、
/// 「已连接但无法访问互联网」，部分应用还会因此不走 Wi-Fi。换成国内能访问的同类地址即可。
///
/// 对应 TS 版的 src/shared/network.ts。
library;

const captiveKeys = <String>[
  'captive_portal_https_url',
  'captive_portal_http_url',
  'captive_portal_fallback_url',
  'captive_portal_other_fallback_urls',
];

/// 国内可以访问、返回 204 的检测地址（google.cn 和原生用的是同一套服务，小米的作为备用）
const captiveCn = <String, String>{
  'captive_portal_https_url': 'https://www.google.cn/generate_204',
  'captive_portal_http_url': 'http://www.google.cn/generate_204',
  'captive_portal_fallback_url': 'http://connect.rom.miui.com/generate_204',
  'captive_portal_other_fallback_urls': 'http://www.google.cn/generate_204',
};

class DnsPreset {
  const DnsPreset(this.host, this.label);

  final String host;
  final String label;
}

/// 私人 DNS（DNS over TLS）的常用服务器
const dnsPresets = <DnsPreset>[
  DnsPreset('dns.alidns.com', '阿里 DNS'),
  DnsPreset('dot.pub', '腾讯 DNSPod'),
  DnsPreset('one.one.one.one', 'Cloudflare'),
  DnsPreset('dns.google', 'Google'),
];

/// off=关闭，opportunistic=自动（系统默认），hostname=指定服务器
enum PrivateDnsMode {
  off,
  opportunistic,
  hostname;

  static PrivateDnsMode? tryParse(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

class NetworkState {
  const NetworkState({
    required this.captive,
    this.captiveUrl,
    required this.dnsMode,
    this.dnsHost,
  });

  final CaptiveState captive;

  /// 当前的 https 检测地址，default 时为空
  final String? captiveUrl;
  final PrivateDnsMode dnsMode;
  final String? dnsHost;
}

/// 联网检测地址的来源：cn=工具箱改成的国内地址，custom=改成了别的，systemDefault=系统默认
enum CaptiveState { cn, custom, systemDefault }

sealed class NetworkRequest {
  const NetworkRequest();
}

class NetworkStatusRequest extends NetworkRequest {
  const NetworkStatusRequest();
}

class NetworkCaptiveRequest extends NetworkRequest {
  const NetworkCaptiveRequest({required this.fix});

  /// true=改成国内地址，false=恢复系统默认
  final bool fix;
}

class NetworkDnsRequest extends NetworkRequest {
  const NetworkDnsRequest({required this.mode, this.host});

  final PrivateDnsMode mode;
  final String? host;
}

final _dnsHost = RegExp(r'^(?=.*[a-z])([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$', caseSensitive: false);

/// 只接受普通域名（私人 DNS 只能填主机名，不能带协议、端口或路径）
bool validDnsHost(String host) => host.length <= 253 && _dnsHost.hasMatch(host);

/// `settings get` 对没设置过的键输出 null
String? _value(String? v) {
  final t = v?.trim();
  return t == null || t.isEmpty || t == 'null' ? null : t;
}

/// 解析「键=值」形式的输出（一次 adb shell 读完全部键）
NetworkState parseNetworkState(String out) {
  final kv = <String, String>{};
  for (final line in out.split(RegExp(r'\r?\n'))) {
    final i = line.indexOf('=');
    if (i > 0) kv[line.substring(0, i).trim()] = line.substring(i + 1);
  }
  final https = _value(kv['captive_portal_https_url']);
  final http = _value(kv['captive_portal_http_url']);
  final captive = https == null && http == null
      ? CaptiveState.systemDefault
      : https == captiveCn['captive_portal_https_url']
          ? CaptiveState.cn
          : CaptiveState.custom;
  final mode = _value(kv['private_dns_mode']);
  final dnsMode = mode == 'off'
      ? PrivateDnsMode.off
      : mode == 'hostname'
          ? PrivateDnsMode.hostname
          : PrivateDnsMode.opportunistic;
  return NetworkState(
    captive: captive,
    captiveUrl: https ?? http,
    dnsMode: dnsMode,
    dnsHost: dnsMode == PrivateDnsMode.hostname ? _value(kv['private_dns_specifier']) : null,
  );
}
