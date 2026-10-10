import 'dart:async';
import 'lib/data/aggregators/source_aggregator.dart';
import 'package:flutter/foundation.dart';

void main() async {
  debugPrint = (String? message, {int? wrapWidth}) {};
  print("Testing NCIS (tmdb: 4614) S1 E1 on MainFuentes...");
  try {
    final stream = MainFuentes.fetchProgressive(
      tmdbId: 4614,
      tipo: 'tv',
      season: 1,
      episode: 1,
    );
    await for (final list in stream) {
      for (final s in list) {
        print("Found server: ${s['provider']} - ${s['servidor']} - ${s['idioma']}");
      }
    }
    print("Done.");
  } catch (e, st) {
    print("Error: $e\n$st");
  }
}
