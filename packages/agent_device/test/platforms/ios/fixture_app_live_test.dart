@TestOn('mac-os')
@Tags(['ios-live', 'fixture-live'])
library;

import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

import '../../../../../test_apps/agent_device_fixture_app/lib/fixture_ids.dart';
import '../fixture_app_live_test_support.dart';

void main() {
  final gate = Platform.environment['AGENT_DEVICE_FIXTURE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS fixture package live tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_FIXTURE_IOS_LIVE=1 to run',
    );
    return;
  }

  final bundleId =
      Platform.environment['AGENT_DEVICE_FIXTURE_IOS_BUNDLE_ID'] ??
      defaultIosFixtureBundleId;

  late AgentDevice device;
  late String udid;

  setUpAll(() async {
    udid = Platform.environment['AGENT_DEVICE_FIXTURE_IOS_UDID'] ??
        await detectBootedIosSimulatorUdid();
    device = await AgentDevice.open(
      backend: const IosBackend(),
      selector: DeviceSelector(serial: udid),
      sessionName: 'fixture-ios-package',
    );
    print('[fixture-ios] opened session on ${device.device.id}');
  });

  tearDownAll(() async {
    await device.close();
  });

  setUp(() async {
    await relaunchFixtureApp(device, bundleId);
  });

  test(
    'home screen exposes scenario navigation',
    () async {
      await expectVisibleId(device, FixtureIds.homeScenarioTitle);
      await expectVisibleId(device, FixtureIds.homeOpenFormLabButton);
      await expectVisibleId(device, FixtureIds.homeOpenCatalogButton);
      await expectVisibleId(device, FixtureIds.homeOpenStateLabButton);
      await expectVisibleId(device, FixtureIds.homeOpenDiagnosticsButton);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'submits and resets Form Lab through package API interactions',
    () async {
      await tapId(device, FixtureIds.homeOpenFormLabButton);
      await expectVisibleId(device, FixtureIds.formSubmitProfileButton);
      await tapId(device, FixtureIds.formAcceptTestTermsCheckbox);
      await tapId(device, FixtureIds.formSubmitProfileButton);
      await expectIdText(
        device,
        FixtureIds.formSubmissionSummaryText,
        'Saved profile for Taylor Tester (medium priority)',
      );
      await tapId(device, FixtureIds.formResetFormButton);
      await expectIdText(
        device,
        FixtureIds.formSubmissionSummaryText,
        'No profile submitted yet',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'filters Catalog and completes a scenario detail flow',
    () async {
      await tapId(device, FixtureIds.homeOpenCatalogButton);
      await expectIdText(
        device,
        FixtureIds.catalogVisibleTasksText,
        'Visible tasks: 4',
      );
      await typeIntoFieldById(
        device,
        FixtureIds.catalogFilterTasksField,
        'crash\n',
      );
      await expectIdText(
        device,
        FixtureIds.catalogVisibleTasksText,
        'Visible tasks: 1',
      );
      await expectVisibleId(device, FixtureIds.catalogTaskCrashRecovery);
      await expectHiddenId(device, FixtureIds.catalogTaskReleaseChecklist);
      await swipeUp(device, startY: 560, endY: 240);
      await tapId(device, FixtureIds.catalogTaskCrashRecovery);
      await expectVisibleId(
        device,
        FixtureIds.taskDetailMarkScenarioCompleteToggle,
      );
      await tapId(device, FixtureIds.taskDetailMarkScenarioCompleteToggle);
      await expectIdText(
        device,
        FixtureIds.taskDetailStatusText,
        'Scenario status: complete',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'updates State Lab counters, snackbar, and async recommendations',
    () async {
      await tapId(device, FixtureIds.homeOpenStateLabButton);
      await expectIdText(device, FixtureIds.stateBatchCountText, 'Batch count: 2');
      await tapId(device, FixtureIds.stateIncreaseBatchButton);
      await expectIdText(device, FixtureIds.stateBatchCountText, 'Batch count: 3');
      await tapId(device, FixtureIds.stateShowConfirmationSnackbarButton);
      await expectIdText(
        device,
        FixtureIds.stateConfirmationSnackbarText,
        'Confirmation snackbar visible',
      );
      await tapId(device, FixtureIds.stateLoadRecommendationsButton);
      await expectVisibleId(
        device,
        FixtureIds.stateRecommendationWarmCache,
        timeout: const Duration(seconds: 15),
      );
      await expectVisibleId(device, FixtureIds.stateRecommendationCaptureLogs);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'handles Diagnostics dialog, banner toggle, and status sheet',
    () async {
      await swipeUp(device);
      await tapId(device, FixtureIds.homeOpenDiagnosticsButton);
      await expectVisibleId(device, FixtureIds.diagnosticsPermissionBanner);
      await tapId(device, FixtureIds.diagnosticsOpenConfirmationDialogButton);
      await expectVisibleId(device, FixtureIds.diagnosticsDialogTitleText);
      await tapId(device, FixtureIds.diagnosticsConfirmDialogButton);
      await expectIdText(
        device,
        FixtureIds.diagnosticsLatestStatusText,
        'Dialog confirmed',
      );
      await tapId(device, FixtureIds.diagnosticsShowPermissionBannerToggle);
      await expectHiddenId(device, FixtureIds.diagnosticsPermissionBanner);
      await tapId(device, FixtureIds.diagnosticsOpenStatusSheetButton);
      await expectVisibleId(device, FixtureIds.diagnosticsStatusSheetTitleText);
      await tapId(device, FixtureIds.diagnosticsPinStatusSheetButton);
      await expectIdText(
        device,
        FixtureIds.diagnosticsLatestStatusText,
        'Sheet pinned',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}