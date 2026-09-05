# iOS Firebase — what still needs a Mac

Android is finished and verified. iOS is configured in code but has two steps
that cannot be done from Windows. Both are quick; neither blocks anything until
someone actually builds for iPhone.

## 1. Add GoogleService-Info.plist to the Xcode target

`ios/Runner/GoogleService-Info.plist` is on disk and holds the right values
(bundle id `com.rniservices.vendor`, project `rni-home-services`). It is
**not yet referenced by the Xcode project** — `project.pbxproj` mentions no
plist at all.

Editing `project.pbxproj` by hand is how Xcode projects get corrupted, and it
could not be tested here, so it was deliberately left for the Mac:

1. Open `ios/Runner.xcworkspace` in Xcode
2. In the left sidebar, right-click the **Runner** folder → *Add Files to "Runner"…*
3. Select `GoogleService-Info.plist`
4. Tick **Copy items if needed** and make sure **Runner** is checked under
   *Add to targets*
5. Commit the resulting `project.pbxproj` change

Firebase still initialises without this, because `main.dart` passes
`DefaultFirebaseOptions.currentPlatform` from `lib/firebase_options.dart` and
those values are already correct. The plist matters for parts of the Firebase
iOS SDK that read it directly, so it belongs in the target regardless.

## 2. Upload an APNs key to Firebase

**This is the one that actually stops iOS push working**, and it is easy to
miss because nothing about it appears in the Flutter project.

Apple does not let Firebase send to iPhones on its own. Firebase needs an APNs
authentication key from the Apple Developer account:

1. In the Apple Developer portal → *Certificates, Identifiers & Profiles* →
   **Keys** → create a key with **Apple Push Notifications service (APNs)**
   enabled. It downloads a `.p8` file — Apple lets you download it **once**.
2. Note the **Key ID** shown next to it, and the **Team ID** from the top right
   of the developer portal.
3. In Firebase → *Project settings* → **Cloud Messaging** → under *Apple app
   configuration*, upload the `.p8` with that Key ID and Team ID.

Until this is done, an iPhone build installs and runs fine and simply never
receives a notification — no error, no crash, nothing in the logs worth
noticing.

This needs the paid Apple Developer account, which per the handover document is
still to be opened and is the slowest item on that list.

## 3. Register the bundle id with Apple

`com.rniservices.vendor` must exist as an App ID in the Apple Developer
portal, with **Push Notifications** capability enabled, before a build can be
signed for a real device or uploaded.

---

Nothing here affects Android, the website build, or the backend.
