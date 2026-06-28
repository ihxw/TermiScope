# TermiScope Mobile

TermiScope Mobile is the native mobile client for TermiScope.

## Direction

This app is the only active mobile codebase after removing the old Ionic/Angular prototype.

Target stack:

- Flutter
- Provider for the current transition phase
- Dart `xterm` for SSH terminal rendering
- `web_socket_channel` for SSH and monitor realtime streams
- Native plugins for file picking, downloads, sharing, notifications, secure storage, and app lifecycle handling

The long-term architecture is documented in:

```text
../../docs/MOBILE_APP_ARCHITECTURE_REALTIME_PLAN.md
```

## Current Refactor Status

Completed:

- App shell and theme code split out of `main.dart`.
- Shared realtime URL builder added under `lib/core/realtime`.
- Terminal and monitor WebSocket services now use the shared URL builder.
- Ionic mobile prototype removed from the repository.

Next steps:

- Move authentication and token refresh into `lib/core/api`.
- Replace scattered `SharedPreferences` token storage with a secure storage adapter.
- Promote terminal, monitor, and SFTP into feature controllers.
- Add a global transfer queue for SFTP upload/download/cross-host transfer.
- Add app lifecycle and network-change reconnection handling.

## Local Development

```bash
cd mobile/flutter_app
flutter pub get
flutter run
```

Android release build:

```bash
cd mobile/flutter_app
flutter build apk --release
```

The current environment used for this repository task did not have `flutter` installed, so local Flutter compilation was not run here.
