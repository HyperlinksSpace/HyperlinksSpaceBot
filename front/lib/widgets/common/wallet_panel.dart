import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../services/wallet/mock_wallet_service.dart';
import '../../services/wallet/wallet_models.dart';
import '../../services/wallet/wallet_service.dart';

class WalletPanel extends StatefulWidget {
  const WalletPanel({
    super.key,
    required this.walletService,
  });

  final WalletService walletService;

  @override
  State<WalletPanel> createState() => _WalletPanelState();
}

class _WalletPanelState extends State<WalletPanel> {
  WalletState? _walletState;
  bool _loading = true;
  bool _creating = false;
  StreamSubscription<WalletState>? _statusSub;

  bool get _isMockGenerating {
    final service = widget.walletService;
    if (service is MockWalletService) {
      return service.isGenerating;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final state = await widget.walletService.loadFromStorage();
    _statusSub = widget.walletService.watchStatus().listen((next) {
      if (!mounted) return;
      setState(() {
        _walletState = next;
      });
    });
    if (!mounted) return;
    setState(() {
      _walletState = state;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _handleCreateWallet() async {
    setState(() {
      _creating = true;
    });
    final created = await widget.walletService.createWallet();
    if (!mounted) return;
    setState(() {
      _walletState = created;
      _creating = false;
    });
  }

  Future<void> _handleRestoreWallet() async {
    final restored = await widget.walletService.restoreWallet();
    if (!mounted) return;
    setState(() {
      _walletState = restored;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            AppTheme.isLightTheme ? const Color(0xFFF3F3F3) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              AppTheme.isLightTheme ? const Color(0xFFE0E0E0) : const Color(0xFF2A2A2A),
        ),
      ),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return _buildGenerating();
    }

    if (_creating || _isMockGenerating) {
      return _buildGenerating();
    }

    if (_walletState == null) {
      return _buildNoWallet();
    }

    final state = _walletState!;
    if (state.deployStatus == DeployStatus.pending) {
      return _buildDeploying(state);
    }
    return _buildReadyOrRestored(state);
  }

  Widget _buildNoWallet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Wallet v1'),
        const SizedBox(height: 8),
        _muted('No wallet found on this device.'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ghostButton('Create Wallet', onTap: _handleCreateWallet),
            _ghostButton('Restore Wallet', onTap: _handleRestoreWallet),
          ],
        ),
      ],
    );
  }

  Widget _buildGenerating() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Wallet v1'),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 10),
            _muted('Creating wallet...'),
          ],
        ),
      ],
    );
  }

  Widget _buildDeploying(WalletState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Wallet v1'),
        const SizedBox(height: 8),
        _addressRow(state.address),
        const SizedBox(height: 12),
        Row(
          children: [
            _badge('Deploying', const Color(0xFFE39A1F)),
            const SizedBox(width: 8),
            _muted('Deploying...'),
          ],
        ),
      ],
    );
  }

  Widget _buildReadyOrRestored(WalletState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _title('Wallet v1'),
            const SizedBox(width: 8),
            _badge(state.restored ? 'Restored' : 'Ready', const Color(0xFF1CA761)),
          ],
        ),
        const SizedBox(height: 8),
        _addressRow(state.address),
        const SizedBox(height: 8),
        _muted('Ready'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricBadge('Allocated', state.allocated, const Color(0xFF3B82F6)),
            _metricBadge('Locked', state.locked, const Color(0xFFE39A1F)),
            _metricBadge('Available', state.available, const Color(0xFF1CA761)),
          ],
        ),
      ],
    );
  }

  Widget _addressRow(String address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.isLightTheme ? Colors.white : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              address,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Aeroport Mono',
                fontSize: 13,
                color: AppTheme.textColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ghostButton('Copy'),
          const SizedBox(width: 6),
          _ghostButton('QR'),
        ],
      ),
    );
  }

  Widget _ghostButton(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                AppTheme.isLightTheme ? const Color(0xFFCDCDCD) : const Color(0xFF3B3B3B),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Aeroport',
            fontSize: 12,
            color: AppTheme.textColor,
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Aeroport',
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _metricBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Aeroport'),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 12,
                color:
                    AppTheme.isLightTheme ? const Color(0xFF666666) : const Color(0xFFBBBBBB),
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Aeroport',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppTheme.textColor,
      ),
    );
  }

  Widget _muted(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Aeroport',
        fontSize: 13,
        color: Color(0xFF818181),
      ),
    );
  }
}
