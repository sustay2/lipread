import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'badge_service.dart';

class BadgeListener {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static bool _initialized = false;

  /// Start listening to /users/{uid}/badges.
  /// Any NEW badge doc (after initial snapshot) will show a popup.
  static void start(BuildContext context, String uid) {
    stop(); // prevent double listeners

    _initialized = false;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('badges')
        .snapshots()
        .listen((snap) {
      // First snapshot = existing docs; skip popups
      if (!_initialized) {
        _initialized = true;
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final badgeId = change.doc.id;
          BadgeService.showBadgePopup(context, badgeId);
        }
      }
    });
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}