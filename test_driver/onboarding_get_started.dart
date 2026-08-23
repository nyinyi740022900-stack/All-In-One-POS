import 'package:integration_test/integration_test_driver.dart';

/// Driver for `onboarding_get_started_test.dart` — lets `flutter drive
/// --release` run that integration test against a release build, which is
/// the configuration the owner's dead-"Get started" report describes.
Future<void> main() => integrationDriver();
