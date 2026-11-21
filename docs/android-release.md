# Android: signing a release for Google Play

A release build is signed with **your upload key** when
`android/key.properties` exists, and with the debug key when it doesn't
(`android/app/build.gradle.kts`). The debug key is public: a debug-signed
APK is for testing on your own phone, never for Play, and never to hand to
anyone as "the app".

## Once: make the key

```sh
keytool -genkey -v -keystore ~/lookup-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

Keep the file and its passwords somewhere safe (a password manager). If you
lose them, Google has to reset the upload key for the app. Turn on **Play
App Signing** when you create the app in Play Console: Google then holds
the real signing key and this one only proves an upload is yours.

## On your own machine

Copy the keystore to `android/app/upload-keystore.jks` and write
`android/key.properties` (both are git-ignored):

```
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=upload-keystore.jks
```

Then `flutter build appbundle --release`.

## In CI

Add four repository secrets (GitHub › Settings › Secrets and variables ›
Actions). The `android` job writes the two files from them before it builds;
without them it builds with the debug key and says so in a warning.

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ~/lookup-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore's password |
| `ANDROID_KEY_PASSWORD` | the key's password |
| `ANDROID_KEY_ALIAS` | `upload` |

## On-time alerts

Android holds back ordinary alarms while a phone dozes, sometimes for
minutes: too late for a ten-minute heads-up. LookUp schedules to the minute
where Android allows it (`SCHEDULE_EXACT_ALARM`; `NotificationService.schedule`)
and falls back to ordinary timing where it doesn't. On Android 14 and later
the user has to allow it: **Settings › Alerts › On-time alerts** in the app
opens the system switch. Play Console asks why the permission is needed:
"time-critical reminders for sky events that last a few minutes". Check on
a phone that a heads-up arrives on time with the screen off for an hour.
