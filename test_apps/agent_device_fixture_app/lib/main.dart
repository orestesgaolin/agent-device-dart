import 'package:flutter/material.dart';

import 'fixture_ids.dart';

void main() {
  runApp(const AgentDeviceFixtureApp());
}

Widget _identified(String id, Widget child) {
  return Semantics(identifier: id, child: child);
}

Widget _identifiedControl(String id, Widget child) {
  return MergeSemantics(
    child: Semantics(identifier: id, child: child),
  );
}

Widget _identifiedText(String id, String text) {
  return Semantics(
    identifier: id,
    container: true,
    label: text,
    value: text,
    excludeSemantics: true,
    child: Text(text),
  );
}

class AgentDeviceFixtureApp extends StatelessWidget {
  const AgentDeviceFixtureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agent Device Fixture',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent Device Fixture')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _identified(
            FixtureIds.homeScenarioTitle,
            Text(
              'Scenario Lab',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use this fixture app to exercise navigation, forms, dialogs, '
            'lists, loading states, and transient UI surfaces.',
          ),
          const SizedBox(height: 16),
          const _LaunchCard(
            title: 'Form Lab',
            description: 'Text input, toggles, validation, and summary output.',
            destinationBuilder: FormLabScreen.new,
            launchButtonId: FixtureIds.homeOpenFormLabButton,
          ),
          const _LaunchCard(
            title: 'Catalog',
            description: 'Search, filter, list navigation, and detail state.',
            destinationBuilder: CatalogScreen.new,
            launchButtonId: FixtureIds.homeOpenCatalogButton,
          ),
          const _LaunchCard(
            title: 'State Lab',
            description: 'Counters, sliders, snackbars, and async loading.',
            destinationBuilder: StateLabScreen.new,
            launchButtonId: FixtureIds.homeOpenStateLabButton,
          ),
          const _LaunchCard(
            title: 'Diagnostics',
            description: 'Dialogs, bottom sheets, and visible status banners.',
            destinationBuilder: DiagnosticsScreen.new,
            launchButtonId: FixtureIds.homeOpenDiagnosticsButton,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Fixture Version'),
                  SizedBox(height: 8),
                  Text('build-channel: integration'),
                  Text('navigation-mode: explicit routes'),
                  Text('surfaces: forms, lists, dialogs, sheets, loading'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget Function({Key? key}) destinationBuilder;
  final String launchButtonId;

  const _LaunchCard({
    required this.title,
    required this.description,
    required this.destinationBuilder,
    required this.launchButtonId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 16),
            _identifiedControl(
              launchButtonId,
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => destinationBuilder(),
                    ),
                  );
                },
                child: Text('Open $title'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormLabScreen extends StatefulWidget {
  const FormLabScreen({super.key});

  @override
  State<FormLabScreen> createState() => _FormLabScreenState();
}

class _FormLabScreenState extends State<FormLabScreen> {
  final _nameController = TextEditingController(text: 'Taylor Tester');
  final _emailController = TextEditingController(text: 'taylor@example.com');
  final _statusController = TextEditingController(text: 'Ready for replay');

  bool _notificationsEnabled = true;
  bool _acceptedTerms = false;
  String _priority = 'Medium';
  String _submissionSummary = 'No profile submitted yet';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _resetForm() {
    setState(() {
      _nameController.text = 'Taylor Tester';
      _emailController.text = 'taylor@example.com';
      _statusController.text = 'Ready for replay';
      _notificationsEnabled = true;
      _acceptedTerms = false;
      _priority = 'Medium';
      _submissionSummary = 'No profile submitted yet';
    });
  }

  void _submit() {
    setState(() {
      _submissionSummary =
          'Saved profile for ${_nameController.text} (${_priority.toLowerCase()} priority)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _identifiedControl(
            FixtureIds.formProfileNameField,
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
          ),
          const SizedBox(height: 12),
          _identifiedControl(
            FixtureIds.formEmailAddressField,
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email address'),
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(height: 12),
          _identifiedControl(
            FixtureIds.formStatusMessageField,
            TextField(
              controller: _statusController,
              decoration: const InputDecoration(labelText: 'Status message'),
            ),
          ),
          const SizedBox(height: 12),
          _identifiedControl(
            FixtureIds.formEnableNotificationsToggle,
            SwitchListTile(
              title: const Text('Enable notifications'),
              subtitle: const Text('Exercises switch interactions.'),
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() {
                  _notificationsEnabled = value;
                });
              },
            ),
          ),
          _identifiedControl(
            FixtureIds.formAcceptTestTermsCheckbox,
            CheckboxListTile(
              title: const Text('Accept test terms'),
              subtitle: const Text('Required by the fixture workflow.'),
              value: _acceptedTerms,
              onChanged: (value) {
                setState(() {
                  _acceptedTerms = value ?? false;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          _identifiedControl(
            FixtureIds.formPriorityLevelField,
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority level'),
              items: const [
                DropdownMenuItem(value: 'Low', child: Text('Low')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'High', child: Text('High')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _priority = value;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _identifiedControl(
                FixtureIds.formSubmitProfileButton,
                FilledButton(
                  onPressed: _acceptedTerms ? _submit : null,
                  child: const Text('Submit profile'),
                ),
              ),
              _identifiedControl(
                FixtureIds.formResetFormButton,
                OutlinedButton(
                  onPressed: _resetForm,
                  child: const Text('Reset form'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submission summary',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  _identifiedText(
                    FixtureIds.formSubmissionSummaryText,
                    _submissionSummary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _filterController = TextEditingController();
  bool _urgentOnly = false;

  final List<_ScenarioTask> _tasks = const [
    _ScenarioTask(
      title: 'Release Checklist',
      summary: 'Happy-path smoke flow with visible completion state.',
      urgent: true,
      semanticId: FixtureIds.catalogTaskReleaseChecklist,
    ),
    _ScenarioTask(
      title: 'Offline Mode',
      summary: 'Tests empty-state messaging and fallback copy.',
      urgent: false,
      semanticId: FixtureIds.catalogTaskOfflineMode,
    ),
    _ScenarioTask(
      title: 'Crash Recovery',
      summary: 'Exercises alert handling and retry affordances.',
      urgent: true,
      semanticId: FixtureIds.catalogTaskCrashRecovery,
    ),
    _ScenarioTask(
      title: 'Deep Links',
      summary: 'Nested navigation with detail verification.',
      urgent: false,
      semanticId: FixtureIds.catalogTaskDeepLinks,
    ),
  ];

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _filterController.text.trim().toLowerCase();
    final visibleTasks = _tasks.where((task) {
      if (_urgentOnly && !task.urgent) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return task.title.toLowerCase().contains(query) ||
          task.summary.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Catalog')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _identifiedControl(
            FixtureIds.catalogFilterTasksField,
            TextField(
              controller: _filterController,
              decoration: const InputDecoration(labelText: 'Filter tasks'),
              onChanged: (_) {
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 12),
          _identifiedControl(
            FixtureIds.catalogShowUrgentOnlyToggle,
            SwitchListTile(
              title: const Text('Show urgent tasks only'),
              value: _urgentOnly,
              onChanged: (value) {
                setState(() {
                  _urgentOnly = value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          _identified(
            FixtureIds.catalogVisibleTasksText,
            Text('Visible tasks: ${visibleTasks.length}'),
          ),
          const SizedBox(height: 8),
          for (final task in visibleTasks)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: _identifiedControl(
                task.semanticId,
                ListTile(
                  title: Text(task.title),
                  subtitle: Text(task.summary),
                  trailing: Text(task.urgent ? 'Urgent' : 'Normal'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TaskDetailScreen(task: task),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TaskDetailScreen extends StatefulWidget {
  final _ScenarioTask task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.task.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _identified(
              FixtureIds.taskDetailSummaryText,
              Text(widget.task.summary),
            ),
            const SizedBox(height: 16),
            _identifiedControl(
              FixtureIds.taskDetailMarkScenarioCompleteToggle,
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mark scenario complete'),
                value: _completed,
                onChanged: (value) {
                  setState(() {
                    _completed = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            _identified(
              FixtureIds.taskDetailStatusText,
              Text(
                _completed
                    ? 'Scenario status: complete'
                    : 'Scenario status: pending',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StateLabScreen extends StatefulWidget {
  const StateLabScreen({super.key});

  @override
  State<StateLabScreen> createState() => _StateLabScreenState();
}

class _StateLabScreenState extends State<StateLabScreen> {
  int _batchCount = 2;
  double _progressTarget = 0.35;
  bool _loading = false;
  List<String> _recommendations = const [];

  Future<void> _loadRecommendations() async {
    setState(() {
      _loading = true;
      _recommendations = const [];
    });

    await Future<void>.delayed(const Duration(milliseconds: 650));

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _recommendations = const [
        'Warm cache before replay',
        'Retry snapshot after animation',
        'Capture logs on failure',
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('State Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _identified(
            FixtureIds.stateBatchCountText,
            Text('Batch count: $_batchCount'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _identifiedControl(
                FixtureIds.stateIncreaseBatchButton,
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _batchCount += 1;
                    });
                  },
                  child: const Text('Increase batch'),
                ),
              ),
              _identifiedControl(
                FixtureIds.stateDecreaseBatchButton,
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _batchCount = (_batchCount - 1).clamp(0, 99);
                    });
                  },
                  child: const Text('Decrease batch'),
                ),
              ),
              _identifiedControl(
                FixtureIds.stateResetBatchButton,
                TextButton(
                  onPressed: () {
                    setState(() {
                      _batchCount = 0;
                    });
                  },
                  child: const Text('Reset batch'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _identified(
            FixtureIds.stateProgressTargetText,
            Text('Progress target: ${(_progressTarget * 100).round()}%'),
          ),
          _identifiedControl(
            FixtureIds.stateProgressSlider,
            Slider(
              value: _progressTarget,
              onChanged: (value) {
                setState(() {
                  _progressTarget = value;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _identifiedControl(
                FixtureIds.stateLoadRecommendationsButton,
                FilledButton(
                  onPressed: _loading ? null : _loadRecommendations,
                  child: const Text('Load recommendations'),
                ),
              ),
              _identifiedControl(
                FixtureIds.stateShowConfirmationSnackbarButton,
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: _identified(
                          FixtureIds.stateConfirmationSnackbarText,
                          const Text('Confirmation snackbar visible'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Show confirmation snackbar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_recommendations.isEmpty)
            const Text('No recommendations loaded yet')
          else
            Card(
              child: Column(
                children: _recommendations
                    .map(
                      (item) => ListTile(
                        title: _identified(_recommendationId(item), Text(item)),
                        dense: true,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _permissionBannerVisible = true;
  String _status = 'Idle';

  Future<void> _showDialogPrompt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: _identified(
            FixtureIds.diagnosticsDialogTitleText,
            const Text('Diagnostics dialog visible'),
          ),
          content: const Text('Use this surface to test modal interactions.'),
          actions: [
            _identifiedControl(
              FixtureIds.diagnosticsDismissDialogButton,
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Dismiss dialog'),
              ),
            ),
            _identifiedControl(
              FixtureIds.diagnosticsConfirmDialogButton,
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm dialog'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == null) {
      return;
    }

    setState(() {
      _status = confirmed ? 'Dialog confirmed' : 'Dialog dismissed';
    });
  }

  Future<void> _showStatusSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identified(
                  FixtureIds.diagnosticsStatusSheetTitleText,
                  Text(
                    'Status sheet visible',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('This bottom sheet stays simple for replay scripts.'),
                const SizedBox(height: 16),
                _identifiedControl(
                  FixtureIds.diagnosticsPinStatusSheetButton,
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop('Sheet pinned'),
                    child: const Text('Pin status sheet'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _status = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_permissionBannerVisible)
            _identified(
              FixtureIds.diagnosticsPermissionBanner,
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const ListTile(
                  title: Text('Permission banner visible'),
                  subtitle: Text(
                    'Transient surfaces should stay easy to dismiss.',
                  ),
                ),
              ),
            ),
          _identifiedControl(
            FixtureIds.diagnosticsShowPermissionBannerToggle,
            SwitchListTile(
              title: const Text('Show permission banner'),
              value: _permissionBannerVisible,
              onChanged: (value) {
                setState(() {
                  _permissionBannerVisible = value;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _identifiedControl(
                FixtureIds.diagnosticsOpenConfirmationDialogButton,
                FilledButton(
                  onPressed: _showDialogPrompt,
                  child: const Text('Open confirmation dialog'),
                ),
              ),
              _identifiedControl(
                FixtureIds.diagnosticsOpenStatusSheetButton,
                OutlinedButton(
                  onPressed: _showStatusSheet,
                  child: const Text('Open status sheet'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  _identifiedText(
                    FixtureIds.diagnosticsLatestStatusText,
                    _status,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioTask {
  final String title;
  final String summary;
  final bool urgent;
  final String semanticId;

  const _ScenarioTask({
    required this.title,
    required this.summary,
    required this.urgent,
    required this.semanticId,
  });
}

String _recommendationId(String item) {
  switch (item) {
    case 'Warm cache before replay':
      return FixtureIds.stateRecommendationWarmCache;
    case 'Retry snapshot after animation':
      return FixtureIds.stateRecommendationRetrySnapshot;
    case 'Capture logs on failure':
      return FixtureIds.stateRecommendationCaptureLogs;
  }
  return item;
}
