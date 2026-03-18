# planarity

## Firebase auth setup

This app now expects FlutterFire's generated options file at [lib/firebase_options.dart](/Users/wxlfe/Documents/Code/planarity/lib/firebase_options.dart). The checked-in file is only a placeholder so the project stays buildable until you generate the real config.

Run this from the project root once `flutter` is available in your shell:

```sh
flutterfire configure
```

That command should overwrite [lib/firebase_options.dart](/Users/wxlfe/Documents/Code/planarity/lib/firebase_options.dart) with real values for the platforms you select. If you want Android, iOS, and macOS auth to work, make sure the Firebase apps you register match these bundle/application IDs already present in the repo:

- Android: `dev.wxlfe.planarity`
- iOS: `dev.wxlfe.planarity`
- macOS: `dev.wxlfe.planarity`

After `flutterfire configure`, email/password auth should work through the existing sign-in and sign-up flow in the app.

For Google auth, also enable the Google provider in Firebase Authentication. Native platforms still need their Firebase apps and OAuth client setup to match the bundle/application IDs above, and web needs the authorized domain configured in Firebase.
