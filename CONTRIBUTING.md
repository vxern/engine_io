# Pre-requisites

In order to contribute, you will need to ensure that you have the latest version
of the Dart SDK installed.

To check the version of your Dart installation, run the following command:

```
dart --version
```

If your version is below 3.0.0 (Dart 3.0), or if your system cannot detect the
SDK in the first place, you should get the latest version through following
[this guide](https://dart.dev/get-dart).

**Note**: The latest version of the Dart SDK is included in Flutter
installations, so if you have the Flutter SDK installed, you should instead
upgrade Flutter using the following command:

```
flutter upgrade
```

# Setup

This project uses [`melos`](https://pub.dev/packages/melos), a tool for managing
the constituent packages in the monorepo.

To install `melos`, run the following command:

```
dart pub global activate melos
```

It is a bit wordy, but in practice, it simply installs the `melos` package
globally (meaning it can be used in the shell like any other program).

Once you have the `melos` package installed, run its `bootstrap` command in the
root directory of the repository (run it in the directory that this file is in):

```
melos bootstrap
```

# Contributing

Before committing, run the following command and fix any issues that crop up:

```
melos run tests
```
