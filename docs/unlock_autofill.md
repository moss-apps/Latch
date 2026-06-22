# Unlock Autofill

Latch can delegate its unlock credential (PIN or password) to the system
autofill provider — Google Password Manager, Bitwarden, Samsung Pass, etc.
External password managers can **fill** the unlock field and **save** the
credential after a successful unlock.

The feature is **off by default**. Enable in Security Settings → "Autofill
Credential", behind a 10-second countdown warning dialog.

## How it works

### Fill (autofill hints)

When enabled, the unlock screen's `TextField` (password mode) and
`PinInputWidget`'s hidden `TextField` (PIN mode) get
`autofillHints: [AutofillHints.password]`. Android's autofill framework
exposes these fields to registered autofill services, which can offer to
fill a saved credential into the field.

### Save prompt

Both auth widgets are wrapped in an `AutofillGroup` (default
`onDisposeAction: AutofillContextAction.commit`):

- **Successful unlock** → `pushReplacement` replaces the screen → the
  `AutofillGroup` disposes with commit → the autofill framework sees the
  committed field values → password manager shows "Save password?".
- **Failed unlock** → the screen stays → no disposal → no save prompt.
- **App exit from unlock** → group disposes → save prompt may or may not
  appear (OS-dependent).

## Implementation

```
lib/services/auth_service.dart       isUnlockAutofillEnabled() / setUnlockAutofillEnabled()
lib/widgets/pin_input_widget.dart    autofillEnabled param → autofillHints on hidden TextField
lib/screens/unlock_screen.dart       _autofillEnabled state, _wrapAutofill() with AutofillGroup
lib/screens/change_security_screen.dart  toggle card + _AutofillWarningDialog (10s countdown)
```

The setting is persisted in `FlutterSecureStorage` under the key
`unlock_autofill_enabled` — same pattern as the biometric toggle.

## Security model

| Path | Credential storage |
|---|---|
| **Biometric unlock** (default) | KWK encrypted inside Android Keystore, never exposed |
| **Autofill unlock** (opt-in) | Credential handed to the chosen autofill provider outside Latch's enclave |

Autofill delegates the "something you know" factor to a third-party
password manager. A compromised autofill provider, a malicious app with
autofill permissions, or a phishing autofill dialog could leak the vault
unlock credential.

The 10-second countdown and explicit warning text surface these risks
before activation. Biometric unlock remains the recommended convenience
path and is placed above autofill in the security settings UI.
