# Feedback Drawer Implementation Plan

Use the approved design and the Office worker rules.
The lead owns integration, source commits, APK checks, and the owner handoff.

Goal: Open feedback from a small side drawer without changing host page bounds.
Structure: Shared `feedback_relay` control and a thin Ohridski Prolog adapter.
Tools: Flutter, Dart, the existing capture plugin, and the existing relay.
No new package or server change is needed.

## Shared tool

- [ ] Create `feedback_relay/lib/src/ui/feedback_drawer.dart`.
- [ ] Export it from `feedback_relay/lib/feedback_relay.dart`.
- [ ] Update `feedback_relay/lib/src/ui/feedback_entry.dart` for full-flow completion.
- [ ] Update `feedback_preview.dart` if preview close must wait for route exit.
- [ ] Add `feedback_relay/test/feedback_drawer_test.dart`.
- [ ] Update the existing capture tests for completion and cancellation.
- [ ] Document the drawer in `feedback_relay/README.md`.
- [ ] Set the shared package version to `0.3.0`.
- [ ] Reset the local capture child position to zero after capture closes.
- [ ] Use `feedback: path: ../feedback` inside the shared Git package.
- [ ] End capture work when its host is removed.
- [ ] Check the local capture package tests and analysis.

Use this public contract:

```dart
FeedbackDrawerOverlay(
  navigatorKey: navigatorKey,
  child: appNavigator,
  onOpenSavedReports: openSavedReports,
  onResult: onResult,
  feedbackLabel: 'Feedback',
  sendLabel: 'Send feedback',
  savedLabel: 'Saved reports',
  closeLabel: 'Close feedback',
)
```

`onOpenSavedReports` returns `Future<void>`.
`onResult` keeps the existing `DeliveryResult` callback contract.
Use keys `feedback_drawer_tab`, `feedback_drawer_send`, and `feedback_drawer_saved`.
Use `feedback_drawer_close` for the close action.

The closed control uses `Stack` with a full-size host child.
The small tab has a touch area of at least 48 logical pixels.
Use the right edge and device safe area.
The open drawer uses a root `PopupRoute`.
Keep its width within the screen on small devices.
Use scrollable contents for larger text and keyboard space.
Back, Close, and outside tap dismiss the drawer.
Do not add a second host `Scaffold`.

Keep the tab hidden while the drawer or capture flow is open.
Close the drawer and await its `completed` future before an action.
Obtain the restored host navigator context after that wait.
Capture must name the host route, not the drawer route.
Restore the tab after dismissal, capture cancellation, preview exit, or failure.
Wait for the capture reverse animation before restoring the tab.
Report errors through `FlutterError` after cleanup.
Keep host page bounds and position unchanged after capture closes.
Reject repeated opening while one flow is active.
Remove temporary listeners when the flow ends or the control is disposed.

Change `openFeedbackCapture` to complete after the whole UI flow ends.
On submit, mark the submitted state before `controller.hide`.
Do not treat that hide as capture cancellation.
On capture cancellation, complete the future without saving or sending.
On preview Send, await send and call the existing result callback.
On Keep, await the saved draft.
On Cancel or outside dismissal, finish without saving or sending.
Wait for preview route exit before restoring the tab.
Propagate failures through the returned future and clean up listeners.
Preserve the report format and draft storage.

Run focused tests from the shared package:

```bash
/home/zarko/Apps/Flutter/sdk/3.38.5/bin/flutter test --no-pub test/feedback_drawer_test.dart test/feedback_widget_test.dart
/home/zarko/Apps/Flutter/sdk/3.38.5/bin/flutter test --no-pub
/home/zarko/Apps/Flutter/sdk/3.38.5/bin/flutter analyze --no-pub
```

Tests must measure equal host bounds with and without the closed control.
Check the normal build returns the host unchanged.
Check Back, outside tap, labels, small screens, and capture order.
Check that the tab stays hidden through capture and preview.
Check Send, Keep, Cancel, and failure all end the future correctly.
Check that submit does not take the cancellation path.
Save actual output in the assigned Office checks folder.

## Host adapter

- [ ] Replace the footer in `lib/feedback/feedback_app_extension.dart` with the shared control.
- [ ] Remove `FeedbackFooterBar` and keep the saved-report page.
- [ ] Supply English and Serbian drawer labels.
- [ ] Replace footer tests in `test/feedback/feedback_app_extension_test.dart`.
- [ ] Check full-size host geometry and restored host route facts.
- [ ] Pin the checked shared tool commit in `pubspec.yaml`.
- [ ] Run `flutter pub get` once to refresh the lock and setup files.
- [ ] Run all host tests and compare analysis with build 80.

Keep the existing `buildFooter` hook name for compatibility.
Do not add feedback imports to the normal app files.
Keep the language fix and date fix.
The lead owns the package pin and generated setup files.
Never edit generated Flutter setup files by hand.

## Review and build

- [ ] Get independent review of both source scopes.
- [ ] Fix faults and run the affected checks.
- [ ] Commit and push only owned source paths.
- [ ] Bind setup inputs to the checked app commit.
- [ ] Build `1.2.8-test`, build `81`, from `lib/main_feedback.dart`.
- [ ] Verify package, signer, version, APK hash, and secret boundaries.

## Disposable device and handoff

- [ ] Use only `emulator-5580` and `OP2_FACTORY_API36_X64`.
- [ ] Install exact build 80 and save a local draft through its old entry.
- [ ] Update to build 81 and check the draft and saved language remain.
- [ ] Check the old footer is absent and the host uses the full height.
- [ ] Check drawer open, outside tap, Back, capture cancellation, and saved reports.
- [ ] Send one image report and check the exact image bytes on GitHub.
- [ ] View the image and check it has no drawer or edge tab.
- [ ] Check fresh language choice, English, Serbian, restart, date, and manual About.
- [ ] Get final review of the APK and device proof.
- [ ] Share only checked APK files through Tailscale.
- [ ] Keep old test APK links and unrelated service routes working.
- [ ] Keep issues 32 and 36 open for the owner.
- [ ] Stop only the disposable emulator after proof is saved.

Owner acceptance stays open.
No physical phone action, store upload, server deployment, or new paid call is allowed.
