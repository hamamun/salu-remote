import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/deep_link.dart';
import '../core/pc_address.dart';
import '../core/prefs.dart';
import 'qr_scan.dart';
import 'theme.dart';
import 'widgets.dart';

/// The one place pairing happens (`remote_apk_ui.md` §2.1): a sheet that
/// slides up only when a connection is missing or the user taps the header.
///
/// First launch = the Connect sheet; every launch after that = straight to
/// Play, already connected. It is also the diagnostics card — the address,
/// the PC's version and the round trip live here, nowhere else.
class ConnectSheet extends StatefulWidget {
  const ConnectSheet({super.key, this.prefill});

  /// A QR that was just scanned (in-app or through the system camera app).
  /// The sheet pre-fills both fields and connects at once — scanning *is*
  /// the pairing, no second tap.
  final PairLink? prefill;

  static void show(BuildContext context, {PairLink? prefill}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => ConnectSheet(prefill: prefill),
    );
  }

  @override
  State<ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<ConnectSheet> {
  final SaluClient _client = SaluClient.instance;
  late final TextEditingController _address;
  late final TextEditingController _code;
  bool _popped = false;

  /// The sheet opened for a missing connection closes itself when the link
  /// lands; one opened from the header while online stays put.
  late final bool _wasOffline;

  @override
  void initState() {
    super.initState();
    final RemotePrefs prefs = RemotePrefs.instance;
    _address = TextEditingController(
      text: widget.prefill?.address ??
          _client.address.value ??
          (prefs.host != null ? '${prefs.host}:${prefs.port ?? 7258}' : ''),
    );
    _code = TextEditingController(text: widget.prefill?.code ?? '');
    _wasOffline = !_client.isOnline;
    _client.link.addListener(_onLink);
    if (widget.prefill != null) {
      // After the first frame, so the sheet (and its ScaffoldMessenger) is
      // in the tree before anything wants to talk to the user.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_connect());
      });
    }
  }

  @override
  void dispose() {
    _client.link.removeListener(_onLink);
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onLink() {
    if (_popped || !mounted) return;
    if (_wasOffline && _client.link.value == LinkState.online) {
      _popped = true;
      Navigator.of(context).pop();
      return;
    }
    // The dot, the button label and the diagnostics block all read the link
    // state straight from the client, so a change must repaint the sheet.
    setState(() {});
  }

  Future<void> _connect() async {
    final String raw = _address.text.trim();
    if (raw.isEmpty) {
      _say('Type the PC address first — it is shown in the PC\'s Remote panel.');
      return;
    }
    final PcAddress? target = PcAddress.parse(raw);
    if (target == null) {
      _say('That does not look like an address. Try the form 192.168.0.12:7258.');
      return;
    }
    final String code = _code.text.trim();
    if (code.isEmpty && RemotePrefs.instance.token == null) {
      // Without a token the PC can only accept a pairing code; sending an
      // empty `auth` would just come back `bad_code`. Say so up front.
      _say('Type the pairing code from the PC\'s Remote panel (first time only).');
      return;
    }
    // Show the user exactly what will be dialled.
    _address.text = target.toString();
    await _client.connect(
      host: target.host,
      port: target.port,
      code: code.isEmpty ? null : code,
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanQr() async {
    final PairLink? link = await QrScanScreen.open(context);
    if (link == null || !mounted) return;
    _address.text = link.address;
    _code.text = link.code;
    await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final LinkState state = _client.link.value;
    return Padding(
      // The keyboard must push the sheet up, not cover the fields.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOutline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                _dot(state),
                const SizedBox(width: 10),
                Text('Connect to your PC', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'On the PC: right-click the picture → Remote. The panel shows the '
              'address, a QR and a code. Scan the QR or type them here once — '
              'after that this app remembers your PC forever.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: state == LinkState.connecting ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan the QR code'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'PC address',
                hintText: '192.168.0.12:7258',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: RemotePrefs.instance.token == null
                    ? 'Pairing code (only the first time)'
                    : 'Pairing code (only if the PC forgot this phone)',
                hintText: '7K4M-QP2X',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: state == LinkState.connecting ? null : _connect,
                child: Text(state == LinkState.connecting ? 'Connecting…' : 'Connect'),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _client.problemMessage,
              builder: (BuildContext context, String? message, Widget? child) {
                if (message == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.info_outline, size: 16, color: AppColors.statusDead),
                      const SizedBox(width: 8),
                      Expanded(child: Text(message)),
                    ],
                  ),
                );
              },
            ),
            if (state == LinkState.online) ...<Widget>[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.videoBackdrop,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceOutline, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FactRow(
                      label: 'PC',
                      value: _client.server.value?.name ?? '—',
                    ),
                    FactRow(label: 'Address', value: _client.address.value ?? '—'),
                    FactRow(
                      label: 'PC version',
                      value: _client.server.value?.version ?? '—',
                    ),
                    ValueListenableBuilder<int?>(
                      valueListenable: _client.latencyMs,
                      builder: (BuildContext context, int? ms, _) => FactRow(
                        label: 'Round trip',
                        value: ms == null ? '—' : '$ms ms',
                      ),
                    ),
                    FactRow(label: 'This phone', value: RemotePrefs.instance.deviceName),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(LinkState state) {
    final Color colour;
    switch (state) {
      case LinkState.online:
        colour = AppColors.statusAlive;
      case LinkState.connecting:
        colour = AppColors.accent;
      case LinkState.needsPairing:
        colour = AppColors.statusDead;
      case LinkState.idle:
      case LinkState.unreachable:
      case LinkState.off:
        colour = AppColors.statusUnknown;
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }
}
