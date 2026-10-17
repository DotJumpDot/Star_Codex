import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository/providers container (Plan/01 §7).
///
/// Populated in later phases as repos land (browse/series/reader/library/
/// updates). UI never constructs repos directly; it watches providers here.
final appProviders = Provider<void>((ref) {});
