# PR Review: #48 — wire(wallet): load existing mnemonic/public-key into copy pages

**PR:** https://github.com/HyperlinksSpace/HyperlinksSpaceBot/pull/48  
**Author:** @SEVAAIGNATYEV  
**Branch:** `wire-mnemonic-wallet` → `main`  
**Scope:** `front/lib/pages/get_page.dart`, `front/lib/pages/mnemonics_page.dart`

---

## Summary

This PR replaces hardcoded placeholder text on the Get (public key) and Mnemonics (seed phrase) pages with real wallet data loaded via `WalletServiceImpl().getExisting()`. Both pages become stateful, use `FutureBuilder` for async loading, and show clear messages when no wallet exists. The approach is correct and the change is a solid step toward production behavior.

**Verdict:** Approve with minor suggestions. Safe to merge after addressing (or explicitly deferring) the items below.

---

## What works well

- **Correct API choice** — Using `getExisting()` (read-only) instead of `getOrCreate()` avoids creating a wallet from these copy-only screens; no side effects when the user just wants to view/copy.
- **Clear empty states** — User-facing messages (“Wallet public key (hex) not found on this device.” / “No mnemonic found on this device.”) are explicit and actionable.
- **Formatting** — Public key chunking (12 chars) and mnemonic grouping (4 words per line) improve readability and match common UX for keys and seeds.
- **Structure preserved** — `CopyableDetailPage`, `onTitleRightTap` (e.g. navigation to Wallets), and layout stay the same; only the data source and loading/empty handling change.

---

## Suggestions

### 1. Avoid copying "Loading..." or error text

If the user taps the copy area before the future completes (or when the wallet is missing), they can copy the literal strings `"Loading..."` or the missing-wallet message. Consider one of:

- Pass an empty string for `copyText` when `snapshot.connectionState != ConnectionState.done` or when `snapshot.data` is a placeholder/message, so tap-to-copy is a no-op until real data is shown; or  
- Keep current behavior but accept that copying “Loading…” / message is an edge case.

**Example (optional):**

```dart
final isPlaceholder = snapshot.connectionState != ConnectionState.done ||
    snapshot.data == _missingAddressText;
return CopyableDetailPage(
  copyText: isPlaceholder ? '' : (snapshot.data ?? ''),
  // ...
);
```

(Apply the same idea on Mnemonics for `_missingMnemonicText` and loading.)

---

### 2. Handle errors from `getExisting()`

`_loadAddressText()` and `_loadMnemonicText()` do not catch exceptions. If storage or crypto fails, `FutureBuilder` will show an error state and the user may see a generic Flutter error. Wrapping in `try/catch` and returning a user-facing string keeps the page usable.

**Example (optional):**

```dart
Future<String> _loadAddressText() async {
  try {
    final wallet = await WalletServiceImpl().getExisting();
    if (wallet == null || wallet.publicKeyHex.trim().isEmpty) {
      return _missingAddressText;
    }
    return _formatForDisplay('Wallet public key (hex)\n${wallet.publicKeyHex}');
  } catch (e) {
    return 'Could not load wallet data. Please try again.';
  }
}
```

(Same pattern for `_loadMnemonicText()`.)

---

### 3. Type parameters in state and formatters

Ensure state classes and list types are fully specified so the code is type-safe and consistent with the rest of the project:

- `State<GetPage>` / `State<MnemonicsPage>` for the state classes.
- `List<String>` in formatters, e.g. `String _formatForDisplay(String value)` already takes `String`; for mnemonics, use `List<String> words` (or whatever `WalletMaterial.mnemonicWords` is) in `_formatMnemonic`.

---

### 4. Style: `FutureBuilder` spacing

Use `FutureBuilder(` (no space before the parenthesis) to match typical Dart style and the rest of the repo.

---

## File-level notes

| File | Note |
|------|------|
| `front/lib/pages/get_page.dart` | All of the above (copy placeholder, error handling, types, spacing). |
| `front/lib/pages/mnemonics_page.dart` | Same: copy placeholder, error handling, `List<String>` in `_formatMnemonic`, spacing. |

---

## Checklist (for author/maintainer)

- [ ] Copy behavior when loading or when wallet is missing is acceptable or updated (e.g. empty `copyText` until data is ready).
- [ ] `getExisting()` failures are caught and surfaced with a user-friendly message.
- [ ] State and list types are explicit (`State<GetPage>`, `State<MnemonicsPage>`, `List<String>`).
- [ ] `FutureBuilder (` → `FutureBuilder(` for style.

Thanks for the PR — the wiring of Get/Mnemonics to real wallet data is a clear improvement.
