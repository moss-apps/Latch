# Unlock Autofill

Latch can delegate its unlock credential (PIN or password) to the system
autofill provider (Google Password Manager, Bitwarden, Samsung Pass, etc.).
External managers can **fill** the unlock field and **save** the credential
after a successful unlock. The feature is **off by default**; enable it in
Security Settings → "Autofill Credential", behind a 10-second countdown
warning.

## How it works

### Fill
When enabled, the unlock screen's `TextField` (password mode) and
`PinInputWidget`'s hidden `TextField` (PIN mode) get
`autofillHints: [AutofillHints.password]`, exposing them to registered
autofill services.

### Save prompt
Both auth widgets are wrapped in an `AutofillGroup`
(`onDisposeAction: AutofillContextAction.commit`):

- **Successful unlock** → `pushReplacement` disposes the group with commit → password manager shows "Save password?".
- **Failed unlock** → screen stays → no disposal → no save prompt.
- **App exit** → group disposes → save prompt may appear (OS-dependent).

## Files

- `lib/services/auth_service.dart`: `isUnlockAutofillEnabled()` / `setUnlockAutofillEnabled()`
- `lib/widgets/pin_input_widget.dart`: `autofillEnabled` param → `autofillHints` on hidden `TextField`
- `lib/screens/unlock_screen.dart`: `_autofillEnabled` state, `_wrapAutofill()` with `AutofillGroup`
- `lib/screens/change_security_screen.dart`: toggle card + `_AutofillWarningDialog` (10s countdown)

Setting persisted in `FlutterSecureStorage` under `unlock_autofill_enabled`
(same pattern as the biometric toggle).

## Security model

| Path | Credential storage |
|---|---|
| **Biometric unlock** (default) | KWK encrypted inside Android Keystore, never exposed |
| **Autofill unlock** (opt-in) | Credential handed to the chosen autofill provider outside Latch's enclave |

Autofill delegates the "something you know" factor to a third-party password
manager. A compromised provider, a malicious app with autofill permissions,
or a phishing autofill dialog could leak the vault unlock credential. The
10-second countdown surfaces these risks before activation. Biometric unlock
remains the recommended path and sits above autofill in the security UI.
