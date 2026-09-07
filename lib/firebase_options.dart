import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDJV5x8PKgWhHBaavZ6z9rB3DuT3TEFtLA",
    authDomain: "aurachat-85f54.firebaseapp.com",
    projectId: "aurachat-85f54",
    storageBucket: "aurachat-85f54.firebasestorage.app",
    messagingSenderId: "539789121540",
    appId: "1:539789121540:android:96ac597e52dd0a80573d51",
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyDJV5x8PKgWhHBaavZ6z9rB3DuT3TEFtLA",
    authDomain: "aurachat-85f54.firebaseapp.com",
    projectId: "aurachat-85f54",
    storageBucket: "aurachat-85f54.firebasestorage.app",
    messagingSenderId: "539789121540",
    appId: "1:539789121540:android:96ac597e52dd0a80573d51",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyDJV5x8PKgWhHBaavZ6z9rB3DuT3TEFtLA",
    authDomain: "aurachat-85f54.firebaseapp.com",
    projectId: "aurachat-85f54",
    storageBucket: "aurachat-85f54.firebasestorage.app",
    messagingSenderId: "539789121540",
    appId: "1:539789121540:ios:96ac597e52dd0a80573d51",
  );
}
