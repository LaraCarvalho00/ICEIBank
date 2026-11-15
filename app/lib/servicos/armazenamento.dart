import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../modelos.dart';

/// Armazenamento local (offline-first) com `shared_preferences`.
///
/// O volume é pequeno (algumas contas, uma fila curta de operações), então um
/// par chave -> JSON resolve, funciona igual em Android, iOS, web e macOS e não
/// exige esquema/migração como o sqflite. Tudo é gravado a cada mudança: se o
/// app for fechado offline, a fila e o saldo em cache sobrevivem.
class Armazenamento {
  Armazenamento._(this._prefs);

  static Future<Armazenamento> abrir() async =>
      Armazenamento._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kToken = 'iceibank.token';
  static const _kUsuario = 'iceibank.usuario';
  static const _kHost = 'iceibank.host';
  static const _kContas = 'iceibank.contas';
  static const _kFila = 'iceibank.fila';
  static const _kHistorico = 'iceibank.historicoSync';

  String? get token => _prefs.getString(_kToken);
  String? get usuario => _prefs.getString(_kUsuario);
  String? get host => _prefs.getString(_kHost);

  Future<void> salvarSessao(String? token, String? usuario) async {
    if (token == null) {
      await _prefs.remove(_kToken);
      await _prefs.remove(_kUsuario);
    } else {
      await _prefs.setString(_kToken, token);
      await _prefs.setString(_kUsuario, usuario ?? '');
    }
  }

  Future<void> salvarHost(String host) => _prefs.setString(_kHost, host);

  Map<int, ContaLocal> lerContas() {
    final bruto = _prefs.getString(_kContas);
    if (bruto == null) return {};
    final lista = (jsonDecode(bruto) as List).cast<Map<String, dynamic>>();
    return {for (final c in lista.map(ContaLocal.fromJson)) c.id: c};
  }

  Future<void> salvarContas(Map<int, ContaLocal> contas) =>
      _prefs.setString(_kContas, jsonEncode(contas.values.map((c) => c.toJson()).toList()));

  List<OperacaoPendente> lerFila() {
    final bruto = _prefs.getString(_kFila);
    if (bruto == null) return [];
    return (jsonDecode(bruto) as List)
        .cast<Map<String, dynamic>>()
        .map(OperacaoPendente.fromJson)
        .toList();
  }

  Future<void> salvarFila(List<OperacaoPendente> fila) =>
      _prefs.setString(_kFila, jsonEncode(fila.map((o) => o.toJson()).toList()));

  List<RegistroSincronizacao> lerHistorico() {
    final bruto = _prefs.getString(_kHistorico);
    if (bruto == null) return [];
    return (jsonDecode(bruto) as List)
        .cast<Map<String, dynamic>>()
        .map(RegistroSincronizacao.fromJson)
        .toList();
  }

  Future<void> salvarHistorico(List<RegistroSincronizacao> historico) =>
      _prefs.setString(_kHistorico, jsonEncode(historico.map((r) => r.toJson()).toList()));
}
