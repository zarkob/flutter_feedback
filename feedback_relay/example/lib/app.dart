/// The example product. This file has no feedback import.
///
/// The development and test entries add the feedback widgets through the
/// slots. The production entry builds the same app without any slot, so the
/// production build holds no feedback control and no sending path.
library;

import 'package:flutter/material.dart';

/// A small product screen set for the example.
class ExampleApp extends StatelessWidget {
  /// Creates the example product.
  const ExampleApp({
    super.key,
    this.feedbackActions = const <Widget>[],
    this.reportsSection,
    this.onScreenChanged,
  });

  /// Extra home actions, for example the feedback entry control.
  final List<Widget> feedbackActions;

  /// An extra home section, for example the saved report list.
  final Widget? reportsSection;

  /// Reports the name of the screen that is open now.
  final ValueChanged<String>? onScreenChanged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Example product',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: HomePage(
        feedbackActions: feedbackActions,
        reportsSection: reportsSection,
        onScreenChanged: onScreenChanged,
      ),
    );
  }
}

/// The home screen of the example product.
class HomePage extends StatefulWidget {
  /// Creates the home screen.
  const HomePage({super.key, this.feedbackActions = const <Widget>[], this.reportsSection, this.onScreenChanged});

  /// Extra home actions.
  final List<Widget> feedbackActions;

  /// An extra home section.
  final Widget? reportsSection;

  /// Reports the name of the screen that is open now.
  final ValueChanged<String>? onScreenChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _items = <String>[];

  @override
  void initState() {
    super.initState();
    widget.onScreenChanged?.call('home');
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.reportsSection;
    return Scaffold(
      appBar: AppBar(title: const Text('Example product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('A small product for the feedback example.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('add_item'),
            onPressed: () => setState(() => _items.add('Item ${_items.length + 1}')),
            child: const Text('Add one item'),
          ),
          const SizedBox(height: 8),
          Text('Items: ${_items.length}', key: const Key('item_count')),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('open_details'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailsPage(
                  feedbackActions: widget.feedbackActions,
                  onScreenChanged: widget.onScreenChanged,
                ),
              ),
            ),
            child: const Text('Open details'),
          ),
          const SizedBox(height: 16),
          ...widget.feedbackActions,
          if (reports != null) ...<Widget>[
            const SizedBox(height: 24),
            Text('Saved reports', style: Theme.of(context).textTheme.titleMedium),
            reports,
          ],
        ],
      ),
    );
  }
}

/// A second screen, so a report can name the screen it came from.
class DetailsPage extends StatefulWidget {
  /// Creates the details screen.
  const DetailsPage({super.key, this.feedbackActions = const <Widget>[], this.onScreenChanged});

  /// Extra actions for this screen.
  final List<Widget> feedbackActions;

  /// Reports the name of the screen that is open now.
  final ValueChanged<String>? onScreenChanged;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  @override
  void initState() {
    super.initState();
    widget.onScreenChanged?.call('details');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('The details screen.'),
          const SizedBox(height: 16),
          ...widget.feedbackActions,
        ],
      ),
    );
  }
}
