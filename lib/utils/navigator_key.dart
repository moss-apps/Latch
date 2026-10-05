import 'package:flutter/material.dart';
import '../services/session_service.dart';

GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
int _generation = -1;

GlobalKey<NavigatorState> get navigatorKey =>
    navigatorKeyForSession(SessionService.instance.generation);

GlobalKey<NavigatorState> navigatorKeyForSession(int generation) {
  if (_generation != generation) {
    _generation = generation;
    _navigatorKey = GlobalKey<NavigatorState>();
  }
  return _navigatorKey;
}
