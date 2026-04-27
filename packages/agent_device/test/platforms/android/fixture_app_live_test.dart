@TestOn('mac-os || linux')
@Tags(['android-live', 'fixture-live'])
library;

import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:agent_device/src/runtime/interaction_target.dart';
import 'package:test/test.dart';

// ignore: avoid_relative_lib_imports
import '../../../../../test_apps/agent_device_fixture_app/lib/fixture_ids.dart';
import '../fixture_app_live_test_support.dart';

void main() {
  final gate = Platform.environment['AGENT_DEVICE_FIXTURE_ANDROID_LIVE'];
  if (gate != '1') {
    test(
      'Android fixture package live tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_FIXTURE_ANDROID_LIVE=1 to run',
    );
    return;
  }

  final packageName =
      Platform.environment['AGENT_DEVICE_FIXTURE_ANDROID_PACKAGE'] ??
      defaultAndroidFixturePackage;

  late AgentDevice device;
  TestRecorder? recorder;

  setUpAll(() async {
    device = await AgentDevice.open(
      backend: const AndroidBackend(),
      selector: DeviceSelector(
        serial: Platform.environment['AGENT_DEVICE_FIXTURE_ANDROID_SERIAL'],
      ),
      sessionName: 'fixture-android-package',
    );
    print('[fixture-android] opened session on ${device.device.id}');
    recorder = createTestRecorder(device, suiteName: 'fixture-android');
    await recorder?.start();
  });

  tearDownAll(() async {
    await recorder?.stop();
    await device.close();
  });

  setUp(() async {
    await relaunchFixtureApp(device, packageName);
  });

  test(
    'home screen exposes scenario navigation',
    () async {
      recorder?.chapter('home screen exposes scenario navigation');
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
      recorder?.chapter('submits and resets Form Lab');
      await tapId(device, FixtureIds.homeOpenFormLabButton);
      await expectVisibleId(device, FixtureIds.formSubmitProfileButton);
      await fillTextFieldById(
        device,
        FixtureIds.formProfileNameField,
        'Morgan Matrix',
      );
      await fillTextFieldById(
        device,
        FixtureIds.formEmailAddressField,
        'morgan@example.com',
      );
      await fillTextFieldById(
        device,
        FixtureIds.formStatusMessageField,
        'Ready to verify on sim',
      );
      await device.pressBack();
      await swipeUp(device, startY: 620, endY: 360);
      await device.wait(
        'visible',
        InteractionTarget.selector(
          'id="${FixtureIds.formAcceptTestTermsCheckbox}"',
        ),
      );
      await tapId(device, FixtureIds.formAcceptTestTermsCheckbox);
      await device.wait(
        'visible',
        InteractionTarget.selector(
          'id="${FixtureIds.formSubmitProfileButton}"',
        ),
      );
      await tapId(device, FixtureIds.formSubmitProfileButton);
      await swipeUp(device, startY: 620, endY: 360);
      await expectIdText(
        device,
        FixtureIds.formSubmissionSummaryText,
        'Saved profile for Morgan Matrix (medium priority)',
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
      recorder?.chapter('filters Catalog and completes detail flow');
      await tapId(device, FixtureIds.homeOpenCatalogButton);
      await expectIdText(
        device,
        FixtureIds.catalogVisibleTasksText,
        'Visible tasks: 4',
      );
      await fillTextFieldById(
        device,
        FixtureIds.catalogFilterTasksField,
        'crash',
      );
      await expectIdText(
        device,
        FixtureIds.catalogVisibleTasksText,
        'Visible tasks: 1',
      );
      await device.pressBack();
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
      recorder?.chapter('updates State Lab counters and snackbar');
      await tapId(device, FixtureIds.homeOpenStateLabButton);
      await expectIdText(
        device,
        FixtureIds.stateBatchCountText,
        'Batch count: 2',
      );
      await tapId(device, FixtureIds.stateIncreaseBatchButton);
      await expectIdText(
        device,
        FixtureIds.stateBatchCountText,
        'Batch count: 3',
      );
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
      recorder?.chapter('handles Diagnostics dialog and status sheet');
      await tapId(device, FixtureIds.homeOpenDiagnosticsButton);
      await expectVisibleId(
        device,
        FixtureIds.diagnosticsOpenConfirmationDialogButton,
      );
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
