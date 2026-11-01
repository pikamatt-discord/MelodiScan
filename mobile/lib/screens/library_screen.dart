import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import '../network/api_client.dart';
import '../widgets/melodiscan_background.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.profile,
    required this.serverUrl,
    required this.apiKey,
    required this.onChangeProfile,
    this.httpClient,
  });

  final UserProfile profile;
  final String serverUrl;
  final String apiKey;
  final Future<void> Function() onChangeProfile;
  final http.Client? httpClient;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  bool _sortByTitle = false;
  final Set<String> _deletingTaskIds = {};

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.serverUrl != widget.serverUrl) {
      _loadLibrary();
    }
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final client = widget.httpClient ?? createApiClient();
    try {
      final uri = Uri.parse('${widget.serverUrl}/api/v1/library').replace(
        queryParameters: {'profile_id': widget.profile.id},
      );
      final response = await client
          .get(
            uri,
            headers:
                widget.apiKey.isEmpty ? null : {'X-API-Key': widget.apiKey},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError(_responseError(response));
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['items'] is! List) {
        throw const FormatException('La bibliothèque reçue est invalide.');
      }
      final items = (body['items'] as List)
          .map((item) {
            if (item is! Map<String, dynamic> ||
                item['task_id'] is! String ||
                item['title'] is! String ||
                item['created_at'] is! String) {
              throw const FormatException(
                  'Une partition de la bibliothèque est invalide.');
            }
            return item;
          })
          .cast<Map<String, dynamic>>()
          .toList(growable: false);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      if (widget.httpClient == null) client.close();
    }
  }

  String _responseError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } on FormatException {
      if (response.body.isNotEmpty) return response.body;
    }
    return 'Le serveur a refusé la bibliothèque (${response.statusCode}).';
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} · $hour:$minute';
  }

  String _normalizeText(String value) {
    const replacements = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
      'œ': 'oe',
    };
    return value.toLowerCase().replaceAllMapped(
          RegExp('[${replacements.keys.join()}]'),
          (match) => replacements[match[0]]!,
        );
  }

  List<Map<String, dynamic>> get _visibleItems {
    final query = _normalizeText(_searchController.text.trim());
    final items = _items.where((item) {
      if (query.isEmpty) return true;
      final title = _normalizeText(item['title'] as String);
      final date = _normalizeText(
        _formatDate(item['created_at'] as String),
      );
      return title.contains(query) || date.contains(query);
    }).toList();
    items.sort((first, second) {
      if (_sortByTitle) {
        return _normalizeText(first['title'] as String)
            .compareTo(_normalizeText(second['title'] as String));
      }
      final firstDate = DateTime.tryParse(first['created_at'] as String);
      final secondDate = DateTime.tryParse(second['created_at'] as String);
      if (firstDate == null || secondDate == null) {
        return (second['created_at'] as String)
            .compareTo(first['created_at'] as String);
      }
      return secondDate.compareTo(firstDate);
    });
    return items;
  }

  void _openScore(Map<String, dynamic> item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          taskId: item['task_id'] as String,
          title: item['title'] as String,
          serverUrl: widget.serverUrl,
          apiKey: widget.apiKey,
          profileId: widget.profile.id,
          httpClient: widget.httpClient,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteScore(Map<String, dynamic> item) async {
    final title = item['title'] as String;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('Supprimer cette partition ?'),
        content: Text(
          '« $title » et ses fichiers enregistrés seront supprimés '
          'définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirm_delete_score'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (shouldDelete == true && mounted) {
      await _deleteScore(item);
    }
  }

  Future<void> _deleteScore(Map<String, dynamic> item) async {
    final taskId = item['task_id'] as String;
    final client = widget.httpClient ?? createApiClient();
    setState(() => _deletingTaskIds.add(taskId));
    try {
      final uri = Uri.parse(
        '${widget.serverUrl}/api/v1/library/$taskId',
      ).replace(queryParameters: {'profile_id': widget.profile.id});
      final response = await client
          .delete(
            uri,
            headers:
                widget.apiKey.isEmpty ? null : {'X-API-Key': widget.apiKey},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 204) {
        throw StateError(_responseError(response));
      }
      if (!mounted) return;
      setState(() {
        _items = _items.where((saved) => saved['task_id'] != taskId).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('« ${item['title']} » a été supprimée.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Suppression impossible : '
              '${error.toString().replaceFirst('Bad state: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingTaskIds.remove(taskId));
      if (widget.httpClient == null) client.close();
    }
  }

  Widget _buildHistoryContent(ThemeData theme) {
    final visibleItems = _visibleItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            'VOTRE COLLECTION',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Vos partitions,\ntoujours à portée de main',
                            style: theme.textTheme.titleLarge?.copyWith(
                              height: 1.16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Profil ${widget.profile.name}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Icon(
                        Icons.library_music_rounded,
                        size: 29,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('history_search_field'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Rechercher une partition',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'MES PARTITIONS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white60,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      '${visibleItems.length} ${visibleItems.length == 1 ? 'partition' : 'partitions'}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 'recent',
                    label: Text('Plus récents'),
                    icon: Icon(Icons.schedule_rounded),
                  ),
                  ButtonSegment(
                    value: 'title',
                    label: Text('Titre A–Z'),
                    icon: Icon(Icons.sort_by_alpha_rounded),
                  ),
                ],
                selected: {_sortByTitle ? 'title' : 'recent'},
                onSelectionChanged: (selection) {
                  setState(() => _sortByTitle = selection.first == 'title');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: visibleItems.isEmpty
              ? SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.search_off_rounded,
                              size: 30,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aucune partition trouvée',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Essayez un autre titre ou une autre date.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  itemCount: visibleItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    final metadata = item['score_metadata'];
                    final measureCount = metadata is Map<String, dynamic>
                        ? metadata['measure_count']
                        : null;
                    return Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openScore(item),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 58,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      theme.colorScheme.primary
                                          .withValues(alpha: 0.23),
                                      theme.colorScheme.secondary
                                          .withValues(alpha: 0.10),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(
                                  Icons.music_note_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 27,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title'] as String,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Wrap(
                                      spacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.calendar_today_rounded,
                                          size: 12,
                                          color: Colors.white54,
                                        ),
                                        Text(
                                          _formatDate(
                                            item['created_at'] as String,
                                          ),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: Colors.white60,
                                          ),
                                        ),
                                        if (measureCount is int) ...[
                                          const Text(
                                            '·',
                                            style: TextStyle(
                                              color: Colors.white38,
                                            ),
                                          ),
                                          Text(
                                            '$measureCount mesures',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.white60,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              IconButton(
                                key: Key('delete_score_${item['task_id']}'),
                                tooltip: 'Supprimer cette partition',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed:
                                    _deletingTaskIds.contains(item['task_id'])
                                        ? null
                                        : () => _confirmDeleteScore(item),
                                icon: _deletingTaskIds.contains(item['task_id'])
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_isLoading && _error == null && _items.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Historique'),
          actions: [
            IconButton(
              tooltip: 'Changer de profil',
              onPressed: widget.onChangeProfile,
              icon: const Icon(Icons.person_outline_rounded),
            ),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _isLoading ? null : _loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: MelodiScanBackground(
          child: _buildHistoryContent(theme),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            tooltip: 'Changer de profil',
            onPressed: widget.onChangeProfile,
            icon: const Icon(Icons.person_outline_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _loadLibrary,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: MelodiScanBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 42),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _loadLibrary,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 82,
                                height: 82,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.library_music_rounded,
                                  size: 38,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Votre collection commence ici',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Les partitions que vous analyserez avec '
                                '${widget.profile.name} seront enregistrées ici.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white60,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Retrouvez vos partitions',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Historique de ${widget.profile.name}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  key: const Key('history_search_field'),
                                  controller: _searchController,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'Rechercher un titre ou une date',
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    suffixIcon: _searchController.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Effacer la recherche',
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() {});
                                            },
                                            icon: const Icon(Icons.close),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      '${_visibleItems.length} '
                                      '${_visibleItems.length > 1 ? 'partitions' : 'partition'}',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const Spacer(),
                                    ChoiceChip(
                                      label: const Text('Récent'),
                                      selected: !_sortByTitle,
                                      onSelected: (_) => setState(
                                        () => _sortByTitle = false,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: const Text('Titre A–Z'),
                                      selected: _sortByTitle,
                                      onSelected: (_) => setState(
                                        () => _sortByTitle = true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _visibleItems.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.search_off_rounded,
                                            size: 44,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Aucune partition trouvée',
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Essayez un autre titre ou une autre date.',
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 20),
                                    itemCount: _visibleItems.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final item = _visibleItems[index];
                                      final metadata = item['score_metadata'];
                                      final measureCount =
                                          metadata is Map<String, dynamic>
                                              ? metadata['measure_count']
                                              : null;
                                      return Card(
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          leading: CircleAvatar(
                                            backgroundColor: theme
                                                .colorScheme.primary
                                                .withValues(alpha: 0.16),
                                            child: Icon(
                                              Icons.music_note_rounded,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                          title: Text(
                                            item['title'] as String,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 5),
                                            child: Text(
                                              '${_formatDate(item['created_at'] as String)}'
                                              '${measureCount is int ? ' · $measureCount mesures' : ''}',
                                            ),
                                          ),
                                          trailing: Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: theme.colorScheme.primary,
                                            size: 30,
                                          ),
                                          onTap: () => _openScore(item),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
