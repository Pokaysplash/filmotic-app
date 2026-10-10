import 'dart:async';
import 'lib/data/extractors/providers/pelisplus_extractor.dart';

void main() async {
  print("Testing Venom (tmdb: 335983) on PelisPlusService...");
  try {
    await for (final map in PelisPlusService.scrape(
      tmdbId: 335983,
      isMovie: true,
      season: 1,
      episode: 1,
    )) {
      print("Found server: $map");
    }
    print("Done.");
  } catch (e, st) {
    print("Error: $e\n$st");
  }
}
