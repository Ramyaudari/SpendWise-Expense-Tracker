# SpendWise (no extra packages)

Files in this zip:
- pubspec.yaml
- lib/main.dart

How to run:
1. Open a terminal in this folder.
2. If there is no android/ or ios/ folder yet, run:  flutter create .
   (it adds the platform folders and keeps lib/main.dart; if it asks to
   overwrite, keep this lib/main.dart and pubspec.yaml)
3. flutter pub get
4. flutter run

Or copy pubspec.yaml and lib/main.dart into an existing Flutter project
named "spendwise" (and delete test/widget_test.dart).

Note: data is kept in memory only, so it is cleared when the app is closed.
