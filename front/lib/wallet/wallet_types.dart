class WalletMaterial {
  final List<String> mnemonicWords;
  final String publicKeyHex;
  final String address;

  const WalletMaterial({
    required this.mnemonicWords,
    required this.publicKeyHex,
    required this.address,
  });

  String get mnemonic => mnemonicWords.join(' ');
}

/// Result of getOrCreate: material and pin when wallet was just created or migrated; both null when wallet exists but is locked.
class WalletCreateResult {
  final WalletMaterial? material;
  final String? pin;

  const WalletCreateResult(this.material, this.pin);
}

abstract class WalletService {
  /// True if wallet exists (encrypted blob or legacy mnemonic).
  Future<bool> hasWallet();

  /// Creates wallet if none; migrates legacy to encrypted if needed. Returns (material, pin) when unlocked; (null, null) when wallet exists and is locked.
  Future<WalletCreateResult> getOrCreate();

  /// Current session material (after create or unlock). Null until user unlocks.
  Future<WalletMaterial?> getExisting();

  /// Unlock with PIN. Returns material and stores in session. Throws on wrong PIN.
  Future<WalletMaterial> unlock(String pin);

  /// PIN for current session (to show on Key page). Null when locked.
  String? getSessionPin();

  /// Clear in-memory session only. Storage unchanged.
  void lock();

  Future<void> clear();
}
