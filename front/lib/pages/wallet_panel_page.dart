import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../telegram_safe_area.dart';
import '../utils/app_haptic.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../widgets/common/pointer_region.dart';
import '../widgets/common/wallet_panel.dart';
import '../widgets/global/global_logo_bar.dart';

/// Wallet panel page: logo bar, bottom bar, scroll, back, and only WalletPanel + state selector.
/// Wallet list (1 wallet, balance, Sendal Rodriges) is on [WalletsPage]. Opened from Creator's page "Wallet Panel" link.
class WalletPanelPage extends StatefulWidget {
  const WalletPanelPage({super.key});

  @override
  State<WalletPanelPage> createState() => _WalletPanelPageState();
}

class _WalletPanelPageState extends State<WalletPanelPage> {
  WalletPanelState _mockPanelState = WalletPanelState.noWallet;
  bool _isCreating = false;

  final Map<String, dynamic> _mockState = {
    'deploy_status': 'pending',
    'dllr_status': 'allocated',
    'address': 'EQC8fT2u...pRk91A',
    'balances': {
      'dllr': {
        'allocated': '10.00',
        'locked': '2.00',
        'available': '8.00',
      }
    }
  };

  /// Mock wallet creation flow: noWallet → generating → deploying → ready.
  /// TODO: Replace with real POST /wallet/create and POST /wallet/deploy (see api_contract_wallet_v1.md).
  void _onCreateWallet() {
    if (_isCreating || _mockPanelState != WalletPanelState.noWallet) return;
    _isCreating = true;
    AppHaptic.heavy();
    setState(() => _mockPanelState = WalletPanelState.generating);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _mockPanelState = WalletPanelState.deploying);
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _mockPanelState = WalletPanelState.ready;
          _isCreating = false;
        });
      });
    });
  }

  /// Mock restore: go to restored state. TODO: Replace with POST /wallet/restore + encrypted blob.
  void _onRestoreWallet() {
    if (_mockPanelState != WalletPanelState.noWallet) return;
    AppHaptic.heavy();
    setState(() => _mockPanelState = WalletPanelState.restored);
  }

  String _stateLabel(WalletPanelState state) {
    switch (state) {
      case WalletPanelState.noWallet:
        return 'No wallet';
      case WalletPanelState.generating:
        return 'Generating';
      case WalletPanelState.deploying:
        return 'Deploying';
      case WalletPanelState.ready:
        return 'Ready';
      case WalletPanelState.restored:
        return 'Restored';
    }
  }

  double _getAdaptiveBottomPadding() {
    final safeAreaInset = TelegramSafeAreaService().getSafeAreaInset();
    return safeAreaInset.bottom + 30;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    final bottomPadding = _getAdaptiveBottomPadding();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: () {
          AppHaptic.heavy();
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        child: Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 570),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 30, 15, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (topPadding == 0.0)
                      const SizedBox(height: 10),
                    WalletPanel(
                      state: _mockPanelState,
                      mockState: _mockState,
                      onCreateWallet: _onCreateWallet,
                      onRestoreWallet: _onRestoreWallet,
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: WalletPanelState.values.map((state) {
                          final selected = _mockPanelState == state;
                          final label = _stateLabel(state);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _mockPanelState = state),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: selected
                                      ? AppTheme.buttonBackgroundColor
                                      : (AppTheme.isLightTheme
                                          ? const Color(0xFFF1F1F1)
                                          : const Color(0xFF222222)),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: 'Aeroport',
                                    fontSize: 12,
                                    color: selected
                                        ? AppTheme.buttonTextColor
                                        : const Color(0xFF818181),
                                  ),
                                ),
                              ),
                            ).pointer,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
