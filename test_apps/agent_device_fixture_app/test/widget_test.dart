import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agent_device_fixture_app/fixture_ids.dart';
import 'package:agent_device_fixture_app/main.dart';

Finder bySemanticId(String id) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.identifier == id,
    description: 'Semantics identifier $id',
  );
}

void main() {
  testWidgets('home screen exposes all fixture labs', (tester) async {
    await tester.pumpWidget(const AgentDeviceFixtureApp());

    expect(find.text('Agent Device Fixture'), findsOneWidget);
    expect(bySemanticId(FixtureIds.homeOpenFormLabButton), findsOneWidget);
    expect(bySemanticId(FixtureIds.homeOpenCatalogButton), findsOneWidget);
    expect(bySemanticId(FixtureIds.homeOpenStateLabButton), findsOneWidget);
    await tester.scrollUntilVisible(
      bySemanticId(FixtureIds.homeOpenDiagnosticsButton),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(bySemanticId(FixtureIds.homeOpenDiagnosticsButton), findsOneWidget);
  });

  testWidgets('form lab submits after accepting terms', (tester) async {
    await tester.pumpWidget(const AgentDeviceFixtureApp());

    await tester.tap(bySemanticId(FixtureIds.homeOpenFormLabButton));
    await tester.pumpAndSettle();

    await tester.tap(bySemanticId(FixtureIds.formAcceptTestTermsCheckbox));
    await tester.pumpAndSettle();
    await tester.tap(bySemanticId(FixtureIds.formSubmitProfileButton));
    await tester.pumpAndSettle();

    expect(
      bySemanticId(FixtureIds.formSubmissionSummaryText),
      findsOneWidget,
    );
    expect(find.textContaining('Saved profile for Taylor Tester'), findsOneWidget);
  });

  testWidgets('state lab loads async recommendations', (tester) async {
    await tester.pumpWidget(const AgentDeviceFixtureApp());

    final stateLabButton = bySemanticId(FixtureIds.homeOpenStateLabButton);
    await tester.scrollUntilVisible(
      stateLabButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(stateLabButton);
    await tester.pumpAndSettle();
    await tester.tap(stateLabButton);
    await tester.pumpAndSettle();
    await tester.tap(bySemanticId(FixtureIds.stateLoadRecommendationsButton));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(bySemanticId(FixtureIds.stateRecommendationWarmCache), findsOneWidget);
    expect(bySemanticId(FixtureIds.stateRecommendationCaptureLogs), findsOneWidget);
  });
}
