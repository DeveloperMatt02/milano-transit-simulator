import 'dart:io';

/// Resident memory of the app process (Android, iOS, desktop).
int? currentRssBytes() => ProcessInfo.currentRss;
