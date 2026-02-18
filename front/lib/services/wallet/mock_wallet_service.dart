import 'dart:async';
import 'wallet_models.dart';
import 'wallet_service.dart';

const Map<String, dynamic> kMockWalletState = {
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

enum WalletMockScenario {
  noWallet,
  generating,
  deploying,
  ready,
  restored,
}

class MockWalletService implements WalletService {
  final StreamController<WalletState> _controller =
      StreamController<WalletState>.broadcast();

  WalletState? _state;
  bool _isGenerating = false;

  bool get isGenerating => _isGenerating;

  static const WalletState _readyState = WalletState(
    address: 'EQC8fT2u...pRk91A',
    deployStatus: DeployStatus.deployed,
    dllrStatus: DllrStatus.available,
    allocated: '10.00',
    locked: '0.00',
    available: '10.00',
    restored: false,
  );

  static const WalletState _restoredState = WalletState(
    address: 'EQC8fT2u...pRk91A',
    deployStatus: DeployStatus.deployed,
    dllrStatus: DllrStatus.available,
    allocated: '10.00',
    locked: '0.00',
    available: '10.00',
    restored: true,
  );

  MockWalletService() {
    _state = _deployingFromMock();
  }

  @override
  Future<WalletState?> loadFromStorage() async => _state;

  @override
  Future<WalletState> createWallet() async {
    _isGenerating = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _isGenerating = false;
    _state = _deployingFromMock();
    _emit();
    return _state!;
  }

  @override
  Future<WalletState> restoreWallet() async {
    _isGenerating = false;
    _state = _restoredState;
    _emit();
    return _state!;
  }

  @override
  Future<WalletState> deployWallet() async {
    _isGenerating = false;
    _state = _deployingFromMock();
    _emit();
    return _state!;
  }

  @override
  Stream<WalletState> watchStatus() async* {
    if (_state != null) {
      yield _state!;
    }
    yield* _controller.stream;
  }

  @override
  Future<void> reset() async {
    _isGenerating = false;
    _state = null;
  }

  void setScenario(WalletMockScenario scenario) {
    switch (scenario) {
      case WalletMockScenario.noWallet:
        _isGenerating = false;
        _state = null;
        return;
      case WalletMockScenario.generating:
        _isGenerating = true;
        _state = null;
        return;
      case WalletMockScenario.deploying:
        _isGenerating = false;
        _state = _deployingFromMock();
        _emit();
        return;
      case WalletMockScenario.ready:
        _isGenerating = false;
        _state = _readyState;
        _emit();
        return;
      case WalletMockScenario.restored:
        _isGenerating = false;
        _state = _restoredState;
        _emit();
        return;
    }
  }

  void _emit() {
    final next = _state;
    if (next != null) {
      _controller.add(next);
    }
  }

  WalletState _deployingFromMock() {
    final balances = (kMockWalletState['balances'] as Map<String, dynamic>);
    final dllr = (balances['dllr'] as Map<String, dynamic>);
    return WalletState(
      address: kMockWalletState['address'] as String,
      deployStatus: DeployStatus.pending,
      dllrStatus: DllrStatus.allocated,
      allocated: dllr['allocated'] as String,
      locked: dllr['locked'] as String,
      available: dllr['available'] as String,
      restored: false,
    );
  }
}
