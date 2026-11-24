# Unlock Autofill

Latch can hand its unlock credential (PIN or password) to the system autofill
provider — Google Password Manager, Bitwarden, Samsung Pass, whatever you use.
That manager can **fill** the unlock field and **save** the credential after a
successful unlock. The feature is **off by default**. You turn it on in Security
Settings → "Autofill Credential", after a 10-second countdown warning.

## How it works

### Filling

When the feature is on, the unlock screen's `TextField` (password mode) and
`PinInputWidget`'s hidden `TextField` (PIN mode) get
`autofillHints: [AutofillHints.password]`, which exposes them to registered
autofill services.

### Save prompt

Both auth widgets are wrapped in an `AutofillGroup` with
`onDisposeAction: AutofillContextAction.commit`:

- **Successful unlock:** `pushReplacement` disposes the group with commit, so the
  password manager shows "Save password?".
- **Failed unlock:** the screen stays, so there's no disposal and no save
  prompt.
- **App exit:** the group disposes, so the save prompt may appear, depending on
  the OS.

## Where the code lives

- `lib/services/auth_service.dart`: `isUnlockAutofillEnabled()` /
  `setUnlockAutofillEnabled()`
- `lib/widgets/pin_input_widget.dart`: `autofillEnabled` param →
  `autofillHints` on the hidden `TextField`
- `lib/screens/unlock_screen.dart`: `_autofillEnabled` state and
  `_wrapAutofill()` with `AutofillGroup`
- `lib/screens/change_security_screen.dart`: toggle card and
  `_AutofillWarningDialog` (10-second countdown)

The setting is stored in `FlutterSecureStorage` under
`unlock_autofill_enabled`, same as the biometric toggle.

## Security model

| Path | Where the credential goes |
|---|---|
| **Biometric unlock** (default) | KWK encrypted inside the Android Keystore; never exposed |
| **Autofill unlock** (opt-in) | Handed to your chosen autofill provider, outside Latch's enclave |

Autofill hands the "something you know" factor to a third-party password
manager. A compromised provider, a malicious app with autofill permissions, or a
phishing autofill dialog could leak the vault unlock credential. The 10-second
countdown exists to make that tradeoff obvious before you turn it on. Biometric
unlock is still the recommended path and sits above autofill in the security UI.
