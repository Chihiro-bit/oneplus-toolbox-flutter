import 'package:test/test.dart';
import 'package:toolbox_core/toolbox_core.dart';

/// 对应 TS 版 test/extras.test.ts 里 parseNetworkState / validDnsHost 的部分
void main() {
  group('parseNetworkState', () {
    test('没改过时是系统默认', () {
      const out = 'captive_portal_https_url=null\ncaptive_portal_http_url=null\n'
          'private_dns_mode=null\nprivate_dns_specifier=null\n';
      final s = parseNetworkState(out);
      expect(s.captive, CaptiveState.systemDefault);
      expect(s.captiveUrl, isNull);
      expect(s.dnsMode, PrivateDnsMode.opportunistic);
      expect(s.dnsHost, isNull);
    });

    test('识别国内地址和指定的 DNS 服务器', () {
      final out = 'captive_portal_https_url=${captiveCn['captive_portal_https_url']}\r\n'
          'private_dns_mode=hostname\r\nprivate_dns_specifier=dns.alidns.com\r\n';
      final s = parseNetworkState(out);
      expect(s.captive, CaptiveState.cn);
      expect(s.captiveUrl, 'https://www.google.cn/generate_204');
      expect(s.dnsMode, PrivateDnsMode.hostname);
      expect(s.dnsHost, 'dns.alidns.com');
    });

    test('别的工具改过的地址算自定义', () {
      final s = parseNetworkState('captive_portal_https_url=https://example.com/204\nprivate_dns_mode=off');
      expect(s.captive, CaptiveState.custom);
      expect(s.dnsMode, PrivateDnsMode.off);
    });

    test('只有 http 地址时算自定义，captiveUrl 取 http 那个', () {
      final s = parseNetworkState('captive_portal_http_url=http://www.google.cn/generate_204\n');
      expect(s.captive, CaptiveState.custom);
      expect(s.captiveUrl, 'http://www.google.cn/generate_204');
    });

    test('私人 DNS 关掉或自动时不输出服务器名', () {
      final off = parseNetworkState('private_dns_mode=off\nprivate_dns_specifier=dns.alidns.com\n');
      expect(off.dnsMode, PrivateDnsMode.off);
      expect(off.dnsHost, isNull);
      final auto = parseNetworkState('private_dns_mode=opportunistic\nprivate_dns_specifier=dns.alidns.com\n');
      expect(auto.dnsMode, PrivateDnsMode.opportunistic);
      expect(auto.dnsHost, isNull);
    });

    test('模式读不出来或为空时按自动处理', () {
      expect(parseNetworkState('private_dns_mode=\n').dnsMode, PrivateDnsMode.opportunistic);
      expect(parseNetworkState('private_dns_mode=whatever\n').dnsMode, PrivateDnsMode.opportunistic);
    });

    test('值里带等号也按第一个等号切分', () {
      expect(parseNetworkState('captive_portal_https_url=a=b\n').captiveUrl, 'a=b');
    });
  });

  group('validDnsHost', () {
    for (final host in ['dns.alidns.com', 'dot.pub', 'one.one.one.one', 'Dns.AliDNS.com']) {
      test('接受 $host', () => expect(validDnsHost(host), isTrue));
    }
    for (final host in [
      'https://dns.google',
      'dns.google:853',
      '1.1.1.1',
      'localhost',
      "a.com'; reboot",
      '',
      '-a.com',
      'a-.com',
      '${'a' * 250}.com',
    ]) {
      test('拒绝 ${host.isEmpty ? '空字符串' : host}', () => expect(validDnsHost(host), isFalse));
    }
  });

  test('内置的检测地址与预设 DNS 都有值', () {
    for (final k in captiveKeys) {
      expect(captiveCn[k], isNotNull, reason: 'captiveCn 缺少 $k');
    }
    expect(captiveKeys.every((k) => captiveCn[k]!.startsWith('http')), isTrue);
    expect(dnsPresets.map((p) => p.host).every(validDnsHost), isTrue);
  });
}
