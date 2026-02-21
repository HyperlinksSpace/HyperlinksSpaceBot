class WalletMaterial {
  final List<String> mnemonicWords;
  final String publicKeyHex;

  const WalletMaterial({
    required this.mnemonicWords,
    required this.publicKeyHex,
  });

  String get mnemonic => mnemonicWords.join(' ');
}

abstract class WalletService {
  Future<WalletMaterial> getOrCreate();
  Future<WalletMaterial?> getExisting();
  Future<void> clear();
}
