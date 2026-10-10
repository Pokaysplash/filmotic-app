import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://www.cinecalidad.my');
  try {
    final response = await http.get(url, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    });
    print('Status: ${response.statusCode}');
    print('Length: ${response.body.length}');
    if (response.statusCode == 200) {
      print('Contains pelicula: ${response.body.contains('pelicula')}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
