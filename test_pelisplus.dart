import 'dart:async';
import 'lib/data/extractors/providers/pelisplus_extractor.dart';

void main() async {
  print("Testing NCIS (tmdb: 4614) S21 E1 on PelisPlusService...");
  try {
    await for (final map in PelisPlusService.scrape(
      tmdbId: 4614,
      isMovie: false,
      season: 21,
      episode: 1,
    )) {
      print("Found server: $map");
    }
    print("Done.");
  } catch (e, st) {
    print("Error: $e\n$st");
  }
}
