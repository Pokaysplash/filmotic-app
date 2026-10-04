// lib/mobil/servicios/fuentes/apis/contenido/detalle_scraper.dart
import '../../models/scraper/detalle_model.dart';
import '../detail/serieskao_detail_scraper.dart';
import '../detail/tioplus_detail_scraper.dart';
import '../detail/cuevana_detail_scraper.dart';
import '../detail/pelisplus_detail_scraper.dart';
import '../detail/cinehax_detail_scraper.dart';
import '../cinecalidad_scraper.dart';
import '../thanhdattoday_scraper.dart';
import '../animeflv_scraper.dart';
import '../canelatv_scraper.dart';
import '../telemundo_scraper.dart';
import '../jkanime_scraper.dart';
import '../tioanime_scraper.dart';

class DetalleScraper {
  static Future<DetalleContenido> fetch({
    required String servicio,
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final s = servicio.toLowerCase().trim();

    print('── DetalleScraper ──────────────────────');
    print('servicio: $s');
    print('url: $url');
    print('titulo: $titulo');
    print('tipo: $tipo');

    try {
      switch (s) {
        case 'serieskao':
          return await DetalleSeriesKao.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'tioplus':
          return await DetalleTioPlus.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'cuevana':
          return await DetalleCuevana.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'pelisplus':
          return await DetallePelisPlus.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'cinehax':
          return await DetalleCineHax.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'cinecalidad':
          return await CinecalidadScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        case 'thanhdattoday':
          return await ThanhDatTodayScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        case 'animeflv':
          return await AnimeFLVScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        case 'canelatv':
          return await CanelaTVScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        case 'telemundo':
          return await TelemundoScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        case 'jkanime':
          return await JKAnimeScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        case 'tioanime':
          return await TioAnimeScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
        default:
          return DetalleContenido(
            ok: false,
            error: 'Servicio no soportado: "$servicio"',
            servicio: servicio,
            titulo: titulo,
            tipo: tipo,
          );
      }
    } catch (e, st) {
      print('ERROR DetalleScraper: $e');
      print(st);
      return DetalleContenido(
        ok: false,
        error: 'Excepción: $e',
        servicio: servicio,
        titulo: titulo,
        tipo: tipo,
      );
    }
  }
}