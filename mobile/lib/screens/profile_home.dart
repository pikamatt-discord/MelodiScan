import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../network/api_client.dart';
import '../widgets/melodiscan_background.dart';
import 'library_screen.dart';
import 'scan_screen.dart';

class ProfileHome extends StatefulWidget {
  const ProfileHome({super.key, this.httpClient});

  final http.Client? httpClient;

  @override
  State<ProfileHome> createState() => _ProfileHomeState();
}

class _ProfileHomeState extends State<ProfileHome> {
  static const _profilePreference = 'account.selected_profile';
  static const _serverPreference = 'connection.server_url';
  static const _apiKeyPreference = 'connection.api_key';

  late final http.Client _client = widget.httpClient ?? createApiClient();
  late final bool _ownsClient = widget.httpClient == null;
  late final TextEditingController _serverController;
  late final TextEditingController _apiKeyController;

  List<UserProfile> _profiles = const [];
  UserProfile? _selectedProfile;
  String? _savedProfileId;
  String? _connectionError;
  bool _isLoading = true;
  int _tabIndex = 0;

  String get _serverUrl => _serverController.text.trim().replaceFirst(
        RegExp(r'/+$'),
        '',
      );
  String get _apiKey => _apiKeyController.text.trim();

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: const String.fromEnvironment(
        'MELODISCAN_API_URL',
        defaultValue: 'http://10.0.2.2:8080',
      ),
    );
    _apiKeyController = TextEditingController(
      text: const String.fromEnvironment('MELODISCAN_API_KEY'),
    );
    _loadPreferencesAndProfiles();
  }

  Future<void> _loadPreferencesAndProfiles() async {
    final preferences = await SharedPreferences.getInstance();
    _serverController.text =
        preferences.getString(_serverPreference) ?? _serverController.text;
    _apiKeyController.text =
        preferences.getString(_apiKeyPreference) ?? _apiKeyController.text;
    _savedProfileId = preferences.getString(_profilePreference);
    await _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _connectionError = null;
      });
    }
    try {
      final response = await _client
          .get(
            Uri.parse('$_serverUrl/api/v1/profiles'),
            headers: _apiKey.isEmpty ? null : {'X-API-Key': _apiKey},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError(_responseError(response));
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['profiles'] is! List) {
        throw const FormatException('Réponse de profils invalide.');
      }
      final profiles = (body['profiles'] as List).map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Profil reçu invalide.');
        }
        return UserProfile.fromJson(item);
      }).toList(growable: false);
      if (profiles.isEmpty) {
        throw const FormatException(
            'Aucun profil n’est configuré sur le serveur.');
      }
      final selected = profiles.where((p) => p.id == _savedProfileId);
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _selectedProfile = selected.isEmpty ? null : selected.first;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _profiles = const [];
          _selectedProfile = null;
          _connectionError = error.toString().replaceFirst('Bad state: ', '');
          _isLoading = false;
        });
      }
    }
  }

  String _responseError(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    } on FormatException {
      if (response.body.isNotEmpty) return response.body;
    }
    return 'Le serveur a refusé la demande (${response.statusCode}).';
  }

  Future<void> _saveConnection() async {
    final preferences = await SharedPreferences.getInstance();
    final savedUrl = await preferences.setString(_serverPreference, _serverUrl);
    final savedKey = await preferences.setString(_apiKeyPreference, _apiKey);
    if (!savedUrl || !savedKey) {
      throw StateError('Impossible d’enregistrer la configuration serveur.');
    }
  }

  Future<void> _selectProfile(UserProfile profile) async {
    try {
      await _saveConnection();
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_profilePreference, profile.id)) {
        throw StateError('Impossible d’enregistrer le profil sélectionné.');
      }
      if (!mounted) return;
      setState(() {
        _savedProfileId = profile.id;
        _selectedProfile = profile;
        _connectionError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _connectionError = error.toString();
        });
      }
    }
  }

  Future<void> _changeProfile() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(_profilePreference)) {
      throw StateError('Impossible de réinitialiser le profil sélectionné.');
    }
    if (!mounted) return;
    setState(() {
      _savedProfileId = null;
      _selectedProfile = null;
    });
    await _loadProfiles();
  }

  Future<void> _saveConnectionFromScan(String serverUrl, String apiKey) async {
    _serverController.text = serverUrl;
    _apiKeyController.text = apiKey;
    await _saveConnection();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _apiKeyController.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _selectedProfile;
    if (_isLoading) {
      return const Scaffold(
        body: MelodiScanBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (profile == null) {
      return _ProfilePicker(
        profiles: _profiles,
        error: _connectionError,
        isLoading: _isLoading,
        serverController: _serverController,
        apiKeyController: _apiKeyController,
        onRefresh: _loadProfiles,
        onSelect: _selectProfile,
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ScanScreen(
            httpClient: _client,
            profileId: profile.id,
            profileName: profile.name,
            initialServerUrl: _serverUrl,
            initialApiKey: _apiKey,
            onChangeProfile: _changeProfile,
            onConnectionChanged: _saveConnectionFromScan,
          ),
          LibraryScreen(
            httpClient: _client,
            profile: profile,
            serverUrl: _serverUrl,
            apiKey: _apiKey,
            onChangeProfile: _changeProfile,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historique',
          ),
        ],
      ),
    );
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({
    required this.profiles,
    required this.error,
    required this.isLoading,
    required this.serverController,
    required this.apiKeyController,
    required this.onRefresh,
    required this.onSelect,
  });

  final List<UserProfile> profiles;
  final String? error;
  final bool isLoading;
  final TextEditingController serverController;
  final TextEditingController apiKeyController;
  final Future<void> Function() onRefresh;
  final Future<void> Function(UserProfile) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sélection du profil')),
      body: MelodiScanBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.26),
                    theme.colorScheme.surface.withValues(alpha: 0.96),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOTRE ESPACE MUSICAL',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Qui utilise\nMelodiScan ?',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choisissez un profil pour retrouver vos partitions.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Icon(
                      Icons.people_alt_rounded,
                      size: 29,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'CHOISIR UN PROFIL',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white60,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            if (error != null) ...[
              Card(
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (final profile in profiles) ...[
              Card(
                key: Key('profile_card_${profile.id}'),
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: isLoading ? null : () => onSelect(profile),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            profile.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: theme.colorScheme.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (profiles.isEmpty || error != null) ...[
              const SizedBox(height: 4),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: Icon(
                      Icons.dns_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Connexion au serveur'),
                    subtitle: const Text('Adresse et clé API'),
                    initiallyExpanded: profiles.isEmpty,
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: serverController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'URL du serveur',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: apiKeyController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Clé API du serveur (si configurée)',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
            if (profiles.isEmpty && error == null)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
