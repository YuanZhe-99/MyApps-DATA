/// Purpose: Test the rule that decides whether data may be sent safely to a
/// WebDAV address.
/// Inputs: None; the addresses are listed in the test.
/// Returns: None.
/// Side effects: None.
/// Notes: This is a security boundary, so the vectors are exhaustive on both
/// sides: what must be allowed, and what must be refused however much it looks
/// like something allowed. Anyone changing the rule should have to change this
/// file first and think about why.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

void main() {
  /// Purpose: Assert that an address is accepted, for the stated reason.
  /// Inputs: The [url], the [reason], and optional [trusted] hosts.
  /// Returns: None.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  void allows(
    String url,
    EndpointReason reason, {
    List<String> trusted = const [],
  }) {
    final verdict = evaluateEndpointUrl(url, trustedHosts: trusted);
    expect(verdict.allowed, isTrue, reason: '$url should be allowed');
    expect(verdict.reason, reason, reason: url);
  }

  /// Purpose: Assert that an address is refused, for the stated reason.
  /// Inputs: The [url], the [reason], and optional [trusted] hosts.
  /// Returns: None.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  void refuses(
    String url,
    EndpointReason reason, {
    List<String> trusted = const [],
  }) {
    final verdict = evaluateEndpointUrl(url, trustedHosts: trusted);
    expect(verdict.allowed, isFalse, reason: '$url should be refused');
    expect(verdict.reason, reason, reason: url);
  }

  group('encrypted', () {
    test('any HTTPS address is fine, wherever it is', () {
      allows('https://cloud.example.com/dav', EndpointReason.https);
      allows('https://8.8.8.8/dav', EndpointReason.https);
    });

    test('the scheme is read case-insensitively', () {
      allows('HTTPS://EXAMPLE.COM', EndpointReason.https);
    });
  });

  group('addresses that cannot leave the network', () {
    test('loopback', () {
      allows('http://localhost:5005/dav', EndpointReason.loopback);
      allows('http://127.0.0.1/dav', EndpointReason.loopback);
      allows('http://127.1.2.3/dav', EndpointReason.loopback);
      allows('http://[::1]:8080/dav', EndpointReason.loopback);
    });

    test('the private IPv4 ranges', () {
      allows('http://10.0.0.5/dav', EndpointReason.privateIpv4);
      allows('http://192.168.1.20:8080/dav', EndpointReason.privateIpv4);
      allows('http://172.16.0.1/dav', EndpointReason.privateIpv4);
      allows('http://172.31.255.254/dav', EndpointReason.privateIpv4);
    });

    test('not the addresses either side of the private block', () {
      // 172.16/12 is a common thing to get wrong by an octet.
      refuses('http://172.15.0.1/dav', EndpointReason.deniedPublicHttp);
      refuses('http://172.32.0.1/dav', EndpointReason.deniedPublicHttp);
    });

    test('link-local', () {
      allows('http://169.254.10.1/dav', EndpointReason.linkLocal);
    });

    test('the range Tailscale hands out from', () {
      allows('http://100.64.0.1/dav', EndpointReason.cgnat);
      allows('http://100.127.255.254/dav', EndpointReason.cgnat);
    });

    test('not the public addresses either side of it', () {
      refuses('http://100.63.0.1/dav', EndpointReason.deniedPublicHttp);
      refuses('http://100.128.0.1/dav', EndpointReason.deniedPublicHttp);
    });

    test('private IPv6', () {
      allows('http://[fd7a:115c:a1e0::1]/dav', EndpointReason.privateIpv6);
      allows('http://[fe80::1]/dav', EndpointReason.privateIpv6);
    });

    test('not public IPv6', () {
      refuses('http://[2001:db8::1]/dav', EndpointReason.deniedPublicHttp);
    });

    test('an IPv4 address wrapped in IPv6 is judged as the IPv4 it is', () {
      // It is what the packets carry, so it is what the rule must look at.
      allows('http://[::ffff:192.168.0.9]/dav', EndpointReason.privateIpv4);
    });
  });

  group('names that only resolve privately', () {
    test('a Tailscale name', () {
      allows('http://nas.tailnet-example.ts.net/dav', EndpointReason.tailnet);
    });

    test('an EasyTier name', () {
      allows('http://node.et.net/dav', EndpointReason.easytier);
    });

    test('an mDNS name', () {
      allows('http://nas.local/dav', EndpointReason.mdns);
      allows('http://nas.local:5005/dav', EndpointReason.mdns);
    });

    test('a bare hostname, which public DNS cannot answer', () {
      allows('http://NAS:8080/dav', EndpointReason.singleLabelHost);
    });

    test('a public host that merely contains a private suffix', () {
      // The attack this rule exists to stop: registering a domain whose name
      // ends up looking like a tailnet.
      refuses(
        'http://evil.ts.net.example.com/dav',
        EndpointReason.deniedPublicHttp,
      );
      refuses(
        'http://nas.local.example.com/dav',
        EndpointReason.deniedPublicHttp,
      );
    });
  });

  group('hosts the user trusted on this device', () {
    test('an exact host is accepted', () {
      allows(
        'http://dav.example.com/dav',
        EndpointReason.trustedHost,
        trusted: ['dav.example.com'],
      );
    });

    test('and is refused without the entry', () {
      refuses('http://dav.example.com/dav', EndpointReason.deniedPublicHttp);
    });

    test('a wildcard covers subdomains', () {
      allows(
        'http://a.example.com/dav',
        EndpointReason.trustedHost,
        trusted: ['*.example.com'],
      );
    });

    test('a wildcard does not cover the bare domain', () {
      // Trusting "*.example.com" says nothing about example.com itself.
      refuses(
        'http://example.com/dav',
        EndpointReason.deniedPublicHttp,
        trusted: ['*.example.com'],
      );
    });

    test(
      'a wildcard does not cover a domain that merely ends the same way',
      () {
        refuses(
          'http://notexample.com/dav',
          EndpointReason.deniedPublicHttp,
          trusted: ['*.example.com'],
        );
      },
    );

    test('entries are matched case-insensitively and untrimmed', () {
      allows(
        'http://DAV.Example.COM/dav',
        EndpointReason.trustedHost,
        trusted: ['  dav.example.com  '],
      );
    });

    test('an empty entry trusts nothing', () {
      refuses(
        'http://dav.example.com/dav',
        EndpointReason.deniedPublicHttp,
        trusted: ['', '   '],
      );
    });
  });

  group('what is refused outright', () {
    test('plain HTTP to a public host', () {
      refuses('http://dav.example.com/dav', EndpointReason.deniedPublicHttp);
      refuses('http://8.8.8.8/dav', EndpointReason.deniedPublicHttp);
    });

    test('any other scheme, however private the host looks', () {
      refuses('ftp://192.168.1.5/dav', EndpointReason.deniedScheme);
      refuses('file:///etc/passwd', EndpointReason.deniedUnparseable);
    });

    test('an address that is not one', () {
      refuses('', EndpointReason.deniedUnparseable);
      refuses('   ', EndpointReason.deniedUnparseable);
      refuses('not a url at all', EndpointReason.deniedUnparseable);
      refuses('https://', EndpointReason.deniedUnparseable);
    });
  });

  group('the verdict itself', () {
    test('names the host it judged, lowercased', () {
      final verdict = evaluateEndpointUrl('https://Cloud.Example.COM/dav');
      expect(verdict.host, 'cloud.example.com');
    });

    test('ignores the port entirely', () {
      // A port says nothing about who can read the traffic.
      final plain = evaluateEndpointUrl('http://192.168.1.5/dav');
      final ported = evaluateEndpointUrl('http://192.168.1.5:8443/dav');
      expect(ported.allowed, plain.allowed);
      expect(ported.reason, plain.reason);
    });
  });

  group('transport class', () {
    test('groups each reason into what the notice shows', () {
      final cases = {
        'https://dav.example.com': EndpointSecurity.encrypted,
        'http://192.168.1.5': EndpointSecurity.privateNetwork,
        'http://nas.local': EndpointSecurity.privateNetwork,
        'http://dav.example.com': EndpointSecurity.insecureHttp,
        'ftp://192.168.1.5': EndpointSecurity.unsupported,
        '': EndpointSecurity.unsupported,
      };
      cases.forEach((url, security) {
        expect(evaluateEndpointUrl(url).security, security, reason: url);
      });
      expect(
        evaluateEndpointUrl(
          'http://dav.example.com',
          trustedHosts: ['dav.example.com'],
        ).security,
        EndpointSecurity.trustedHost,
      );
    });

    test('the Uri entry point agrees with the text entry point', () {
      for (final url in [
        'https://Cloud.Example.com/dav',
        'http://100.64.0.1:8080/dav',
        'http://evil.ts.net.example.com/dav',
        'file:///etc/passwd',
      ]) {
        final fromUri = evaluateEndpointSecurity(Uri.parse(url));
        final fromText = evaluateEndpointUrl(url);
        expect(fromUri.reason, fromText.reason, reason: url);
        expect(fromUri.host, fromText.host, reason: url);
      }
    });
  });
}
