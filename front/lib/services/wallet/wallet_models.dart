enum DeployStatus {
  notStarted,
  pending,
  deployed,
  failed,
}

enum DllrStatus {
  none,
  allocated,
  locked,
  available,
}

class WalletState {
  const WalletState({
    required this.address,
    required this.deployStatus,
    required this.dllrStatus,
    required this.allocated,
    required this.locked,
    required this.available,
    required this.restored,
  });

  final String address;
  final DeployStatus deployStatus;
  final DllrStatus dllrStatus;
  final String allocated;
  final String locked;
  final String available;
  final bool restored;
}
