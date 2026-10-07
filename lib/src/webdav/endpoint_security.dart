/// Purpose: Classify how safely data can travel to a configured endpoint.
/// Inputs: An endpoint address and the hosts this device has been told to trust.
/// Returns: Pure verdicts with a transport class and a named reason.
/// Side effects: None.
/// Notes: The host is judged, never resolved, so the answer does not depend on
/// the network at the moment of asking. Ports are ignored. The rule table is the
/// secure-endpoint rule already promised to users for API-key sync; changing what
/// counts as secure changes that promise.
library;

/// How data would travel to an endpoint.
enum EndpointSecurity {
  /// HTTPS: the transport is encrypted.
  encrypted,

  /// Plain HTTP to an address or name that cannot leave a private network.
  privateNetwork,

  /// Plain HTTP to a host the user trusted on this device.
  trustedHost,

  /// Plain HTTP to a host that could be anywhere.
  insecureHttp,

  /// Neither HTTP nor HTTPS, or not an address at all.
  unsupported,
}

/// Why an address was or was not accepted.
enum EndpointReason {
  /// The connection is encrypted.
  https,

  /// Loopback: the server is this machine.
  loopback,

  /// A private IPv4 range.
  privateIpv4,

  /// A link-local IPv4 address.
  linkLocal,

  /// The carrier-grade NAT range overlay networks allocate from.
  cgnat,

  /// A unique-local or link-local IPv6 address.
  privateIpv6,

  /// A Tailscale name.
  tailnet,

  /// An EasyTier name.
  easytier,

  /// An mDNS name, resolvable only on the local link.
  mdns,

  /// A bare hostname with no dots, which only a local resolver answers.
  singleLabelHost,

  /// A host the user added to this device's trusted list.
  trustedHost,

  /// Plain HTTP to a host that could be anywhere.
  deniedPublicHttp,

  /// Neither HTTP nor HTTPS.
  deniedScheme,

  /// The address could not be read as one.
  deniedUnparseable,
}

/// What the policy decided about one address.
class EndpointVerdict {
  /// Why the address was or was not accepted.
  final EndpointReason reason;

  /// The host that was judged, lowercased, or empty when there was none.
  final String host;

  /// Purpose: Record a verdict.
  /// Inputs: [reason] and the judged [host].
  /// Returns: A new immutable value.
  /// Side effects: None.
  /// Notes: [security] and [allowed] are derived from [reason].
  const EndpointVerdict({required this.reason, required this.host});

  /// Purpose: Report whether the endpoint passes the secure-endpoint rule.
  /// Inputs: None.
  /// Returns: True for HTTPS, private-network HTTP and trusted-host HTTP.
  /// Side effects: None.
  /// Notes: Secret channels exchange data only when this is true, in both
  /// directions.
  bool get allowed => switch (security) {
    EndpointSecurity.encrypted ||
    EndpointSecurity.privateNetwork ||
    EndpointSecurity.trustedHost => true,
    EndpointSecurity.insecureHttp || EndpointSecurity.unsupported => false,
  };

  /// Purpose: Group the reason into the transport class shown to users.
  /// Inputs: None.
  /// Returns: The [EndpointSecurity] class for [reason].
  /// Side effects: None.
  /// Notes: None.
  EndpointSecurity get security => switch (reason) {
    EndpointReason.https => EndpointSecurity.encrypted,
    EndpointReason.trustedHost => EndpointSecurity.trustedHost,
    EndpointReason.deniedPublicHttp => EndpointSecurity.insecureHttp,
    EndpointReason.deniedScheme ||
    EndpointReason.deniedUnparseable => EndpointSecurity.unsupported,
    _ => EndpointSecurity.privateNetwork,
  };
}

/// Purpose: Judge an endpoint address given as text.
/// Inputs: The [url] as typed or stored, and the device's [trustedHosts].
/// Returns: An [EndpointVerdict].
/// Side effects: None.
/// Notes: Blank text, unparseable text and addresses without a host are
/// [EndpointReason.deniedUnparseable]; everything else delegates to
/// [evaluateEndpointSecurity].
EndpointVerdict evaluateEndpointUrl(
  String url, {
  List<String> trustedHosts = const [],
}) {
  final trimmed = url.trim();
  final uri = trimmed.isEmpty ? null : Uri.tryParse(trimmed);
  if (uri == null) {
    return const EndpointVerdict(
      reason: EndpointReason.deniedUnparseable,
      host: '',
    );
  }
  return evaluateEndpointSecurity(uri, trustedHosts: trustedHosts);
}

/// Purpose: Judge whether an endpoint can be reached safely.
/// Inputs: The endpoint [uri], and the [trustedHosts] this device accepts
/// (exact hosts or `*.suffix` wildcards).
/// Returns: An [EndpointVerdict].
/// Side effects: None.
/// Notes: HTTPS is accepted for any host. HTTP is accepted only for loopback,
/// private IPv4, link-local, CGNAT `100.64/10`, IPv6 `fc00::/7` and
/// `fe80::/10`, `*.ts.net`, `*.et.net`, `*.local`, dotless hosts, or trusted
/// hosts. Other schemes are refused. Ports are ignored.
EndpointVerdict evaluateEndpointSecurity(
  Uri uri, {
  List<String> trustedHosts = const [],
}) {
  if (uri.host.isEmpty) {
    return const EndpointVerdict(
      reason: EndpointReason.deniedUnparseable,
      host: '',
    );
  }

  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();

  if (scheme == 'https') {
    return EndpointVerdict(reason: EndpointReason.https, host: host);
  }
  if (scheme != 'http') {
    return EndpointVerdict(reason: EndpointReason.deniedScheme, host: host);
  }

  if (_privateAddress(host) case final reason?) {
    return EndpointVerdict(reason: reason, host: host);
  }
  if (_privateName(host) case final reason?) {
    return EndpointVerdict(reason: reason, host: host);
  }
  if (_isTrusted(host, trustedHosts)) {
    return EndpointVerdict(reason: EndpointReason.trustedHost, host: host);
  }

  return EndpointVerdict(reason: EndpointReason.deniedPublicHttp, host: host);
}

/// Purpose: Recognise an address that cannot be routed off the local network.
/// Inputs: The lowercased [host].
/// Returns: The reason, or null when it is not one.
/// Side effects: None.
/// Notes: Internal helper. An IPv4 address mapped into IPv6 is judged as the
/// IPv4 address the packets carry.
EndpointReason? _privateAddress(String host) {
  final bare = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;

  if (bare == '::1') return EndpointReason.loopback;
  if (bare.startsWith('::ffff:')) {
    final mapped = bare.substring('::ffff:'.length);
    if (mapped.contains('.')) return _privateIpv4(mapped);
  }
  if (bare.contains(':')) {
    // fe80::/10 link-local and fc00::/7 unique-local.
    final head = bare.split(':').first;
    if (head.length >= 2) {
      final prefix = int.tryParse(head.padRight(4, '0'), radix: 16);
      if (prefix != null) {
        if (prefix >= 0xfe80 && prefix <= 0xfebf) {
          return EndpointReason.privateIpv6;
        }
        if (prefix >= 0xfc00 && prefix <= 0xfdff) {
          return EndpointReason.privateIpv6;
        }
      }
    }
    return null;
  }

  return _privateIpv4(bare);
}

/// Purpose: Recognise a private IPv4 address.
/// Inputs: The [address] in dotted form.
/// Returns: The reason, or null.
/// Side effects: None.
/// Notes: Internal helper.
EndpointReason? _privateIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  final octets = [for (final part in parts) int.tryParse(part)];
  if (octets.any((o) => o == null || o < 0 || o > 255)) return null;
  final a = octets[0]!;
  final b = octets[1]!;

  if (a == 127) return EndpointReason.loopback;
  if (a == 10) return EndpointReason.privateIpv4;
  if (a == 172 && b >= 16 && b <= 31) return EndpointReason.privateIpv4;
  if (a == 192 && b == 168) return EndpointReason.privateIpv4;
  if (a == 169 && b == 254) return EndpointReason.linkLocal;
  if (a == 100 && b >= 64 && b <= 127) return EndpointReason.cgnat;
  return null;
}

/// Purpose: Recognise a name that only resolves inside a private network.
/// Inputs: The lowercased [host].
/// Returns: The reason, or null.
/// Side effects: None.
/// Notes: Internal helper. Suffixes match on a label boundary, so
/// `evil.ts.net.example.com` is refused. Addresses are never treated as names.
EndpointReason? _privateName(String host) {
  if (host.contains(':') || RegExp(r'^[0-9.]+$').hasMatch(host)) return null;

  if (host == 'localhost' || host.endsWith('.localhost')) {
    return EndpointReason.loopback;
  }
  if (host.endsWith('.ts.net')) return EndpointReason.tailnet;
  if (host.endsWith('.et.net')) return EndpointReason.easytier;
  if (host.endsWith('.local')) return EndpointReason.mdns;
  if (!host.contains('.')) return EndpointReason.singleLabelHost;
  return null;
}

/// Purpose: Check a host against this device's trusted list.
/// Inputs: The lowercased [host] and the [trustedHosts].
/// Returns: Whether an entry matches.
/// Side effects: None.
/// Notes: Internal helper. Entries are trimmed and case-insensitive; a
/// `*.suffix` entry covers real subdomains only, never the bare domain.
bool _isTrusted(String host, List<String> trustedHosts) {
  for (final raw in trustedHosts) {
    final entry = raw.trim().toLowerCase();
    if (entry.isEmpty) continue;
    if (entry.startsWith('*.')) {
      final suffix = entry.substring(1);
      if (host.endsWith(suffix) && host.length > suffix.length) return true;
    } else if (entry == host) {
      return true;
    }
  }
  return false;
}

/// Purpose: Validate and normalise one trusted-host entry as typed.
/// Inputs: The user's [input].
/// Returns: The trimmed, lowercased host or `*.suffix` entry, or null when it
/// is not a host (for example a URL with a scheme, path or port).
/// Side effects: None.
/// Notes: Same rule as MyTranscribe's trusted-host editor. Someone who pastes
/// `http://nas/dav` has misunderstood the list, and accepting it would trust
/// nothing.
String? normalizeTrustedHostEntry(String input) {
  final entry = input.trim().toLowerCase();
  final valid =
      RegExp(
        r'^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?'
        r'(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$',
      ).hasMatch(entry) &&
      !entry.contains('/') &&
      !entry.contains(':');
  return valid ? entry : null;
}
