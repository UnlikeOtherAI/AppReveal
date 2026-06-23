// Pure Dart mDNS service advertisement for _appreveal._tcp.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MdnsAdvertiser {
  static final shared = MdnsAdvertiser._();
  MdnsAdvertiser._();

  static final _multicastAddress = InternetAddress('224.0.0.251');
  static const _mdnsPort = 5353;
  static const _serviceType = '_appreveal._tcp.local';

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  final _startupTimers = <Timer>[];
  late _ServiceAdvertisement _advertisement;

  Future<void> register({
    required int port,
    required String bundleId,
    required String version,
    String auth = 'session-token',
  }) async {
    await unregister();

    try {
      final addresses = await _localIpv4Addresses();
      _advertisement = _ServiceAdvertisement(
        instanceName: 'AppReveal-$bundleId.$_serviceType',
        hostName: _localHostName(),
        port: port,
        addresses: addresses,
        txt: {
          'bundleId': bundleId,
          'version': version,
          'transport': 'streamable-http',
          'auth': auth,
        },
      );

      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _mdnsPort,
        reuseAddress: true,
        reusePort: true,
        ttl: 255,
      );
      socket.broadcastEnabled = true;
      socket.joinMulticast(_multicastAddress);
      socket.listen(_handleSocketEvent, onError: (_) {});
      _socket = socket;

      _scheduleStartupAnnouncements();
      _announceTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _announce(),
      );
    } catch (e) {
      // mDNS failure is non-fatal; the HTTP server still works by direct URL.
      // ignore: avoid_print
      print('[AppReveal] mDNS registration failed: $e');
    }
  }

  Future<void> unregister() async {
    for (final timer in _startupTimers) {
      timer.cancel();
    }
    _startupTimers.clear();
    _announceTimer?.cancel();
    _announceTimer = null;
    _socket?.close();
    _socket = null;
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    if (_isDnsQuery(datagram.data) && _queryMentionsAppReveal(datagram.data)) {
      _announce();
    }
  }

  void _scheduleStartupAnnouncements() {
    for (final delay in const [
      Duration.zero,
      Duration(milliseconds: 750),
      Duration(seconds: 2),
    ]) {
      _startupTimers.add(Timer(delay, _announce));
    }
  }

  void _announce() {
    final socket = _socket;
    if (socket == null) return;

    final packet = _advertisement.toPacket();
    socket.send(packet, _multicastAddress, _mdnsPort);
  }

  bool _queryMentionsAppReveal(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true).toLowerCase();
    return text.contains('_appreveal') ||
        text.contains('appreveal') ||
        text.contains(_advertisement.hostName.toLowerCase());
  }

  bool _isDnsQuery(Uint8List data) {
    if (data.length < 4) return false;
    return (data[2] & 0x80) == 0;
  }

  static String _localHostName() {
    final raw = Platform.localHostname.trim();
    final host = raw.isEmpty ? 'appreveal' : raw.replaceAll(RegExp(r'\.$'), '');
    return host.endsWith('.local') ? host : '$host.local';
  }

  static Future<List<InternetAddress>> _localIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where((address) => !address.isLoopback)
        .toList();

    return addresses.isEmpty ? [InternetAddress.loopbackIPv4] : addresses;
  }
}

class _ServiceAdvertisement {
  _ServiceAdvertisement({
    required this.instanceName,
    required this.hostName,
    required this.port,
    required this.addresses,
    required this.txt,
  });

  final String instanceName;
  final String hostName;
  final int port;
  final List<InternetAddress> addresses;
  final Map<String, String> txt;

  Uint8List toPacket() {
    final records = <_DnsRecord>[
      _DnsRecord.ptr(MdnsAdvertiser._serviceType, instanceName),
      _DnsRecord.srv(instanceName, port, hostName),
      _DnsRecord.txt(instanceName, txt),
      for (final address in addresses) _DnsRecord.a(hostName, address),
    ];

    final writer = _DnsWriter()
      ..uint16(0)
      ..uint16(0x8400)
      ..uint16(0)
      ..uint16(records.length)
      ..uint16(0)
      ..uint16(0);

    for (final record in records) {
      writer
        ..name(record.name)
        ..uint16(record.type)
        ..uint16(record.dnsClass)
        ..uint32(record.ttl)
        ..uint16(record.data.length)
        ..bytes(record.data);
    }

    return Uint8List.fromList(writer.takeBytes());
  }
}

class _DnsRecord {
  _DnsRecord._({
    required this.name,
    required this.type,
    required this.dnsClass,
    required this.ttl,
    required this.data,
  });

  final String name;
  final int type;
  final int dnsClass;
  final int ttl;
  final List<int> data;

  factory _DnsRecord.ptr(String serviceType, String instanceName) {
    return _DnsRecord._(
      name: serviceType,
      type: 12,
      dnsClass: 1,
      ttl: 120,
      data: (_DnsWriter()..name(instanceName)).takeBytes(),
    );
  }

  factory _DnsRecord.srv(String instanceName, int port, String hostName) {
    final data = _DnsWriter()
      ..uint16(0)
      ..uint16(0)
      ..uint16(port)
      ..name(hostName);
    return _DnsRecord._(
      name: instanceName,
      type: 33,
      dnsClass: 0x8001,
      ttl: 120,
      data: data.takeBytes(),
    );
  }

  factory _DnsRecord.txt(String instanceName, Map<String, String> values) {
    final data = <int>[];
    for (final entry in values.entries) {
      final value = utf8.encode('${entry.key}=${entry.value}');
      if (value.length > 255) continue;
      data
        ..add(value.length)
        ..addAll(value);
    }

    return _DnsRecord._(
      name: instanceName,
      type: 16,
      dnsClass: 0x8001,
      ttl: 120,
      data: data,
    );
  }

  factory _DnsRecord.a(String hostName, InternetAddress address) {
    return _DnsRecord._(
      name: hostName,
      type: 1,
      dnsClass: 0x8001,
      ttl: 120,
      data: address.rawAddress,
    );
  }
}

class _DnsWriter {
  final _bytes = <int>[];

  void uint16(int value) {
    _bytes
      ..add((value >> 8) & 0xff)
      ..add(value & 0xff);
  }

  void uint32(int value) {
    _bytes
      ..add((value >> 24) & 0xff)
      ..add((value >> 16) & 0xff)
      ..add((value >> 8) & 0xff)
      ..add(value & 0xff);
  }

  void bytes(List<int> value) {
    _bytes.addAll(value);
  }

  void name(String fqdn) {
    for (final label in fqdn.split('.')) {
      if (label.isEmpty) continue;
      final encoded = utf8.encode(label);
      if (encoded.length > 63) {
        throw ArgumentError.value(label, 'fqdn', 'DNS label is too long');
      }
      _bytes
        ..add(encoded.length)
        ..addAll(encoded);
    }
    _bytes.add(0);
  }

  List<int> takeBytes() => List<int>.of(_bytes);
}
