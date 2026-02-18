import 'dart:async';
import 'wallet_models.dart';

abstract class WalletService {
  Future<WalletState?> loadFromStorage();
  Future<WalletState> createWallet();
  Future<WalletState> restoreWallet();
  Future<WalletState> deployWallet();
  Stream<WalletState> watchStatus();
  Future<void> reset();
}

class RealWalletService implements WalletService {
  @override
  Future<WalletState?> loadFromStorage() async {
    return null;
  }

  @override
  Future<WalletState> createWallet() {
    throw UnimplementedError('RealWalletService.createWallet is not wired yet.');
  }

  @override
  Future<WalletState> restoreWallet() {
    throw UnimplementedError('RealWalletService.restoreWallet is not wired yet.');
  }

  @override
  Future<WalletState> deployWallet() {
    throw UnimplementedError('RealWalletService.deployWallet is not wired yet.');
  }

  @override
  Stream<WalletState> watchStatus() {
    return const Stream<WalletState>.empty();
  }

  @override
  Future<void> reset() async {}
}
