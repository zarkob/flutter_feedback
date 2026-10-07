# Feedback drawer design

Use a small tab at the right edge.
Tap the tab to open a drawer over the app.
The app keeps the same width and height.
A drawer is a panel that slides in from the side.

The drawer has two actions:

- Send feedback.
- Saved reports.

Tap outside the drawer to close it.
Use Back to close it.
The drawer must close before image capture starts.
The edge tab must stay out of the captured image.

The current app uses a `Column` with an `Expanded` app and a fixed footer.
This takes space from every app page.
Replace that layout with a shared overlay control.
An overlay puts a control over a page.
It does not make the page smaller.
Flutter supports [overlapping controls](https://api.flutter.dev/flutter/widgets/Stack-class.html).

Keep the control in `feedback_relay`.
Other Avensora apps can use the same control.
The host supplies its navigator key and translated labels.
The host can supply its saved-report page action.
The tool supplies the drawer and capture action.

Close the drawer before opening a saved-report page.
Restore the host route before starting capture.
Wait until the drawer leaves the screen.
Hide the tab during capture and preview.
Keep the current report ID, image, preview, and send flow.

## Source plan

Use `Stack` to keep the host child at its full bounds.
Use a root `PopupRoute` for the open drawer.
This is a temporary app route above the current page.
It lets Back and an outside tap close the drawer.
Do not add a second `Scaffold` around the host navigator.

On an action, hide the tab first.
Close the drawer route.
Await that route's `completed` future.
This waits until its last screen layer is gone.
Only then read the host route and open capture or saved reports.

Keep the tab hidden for the whole capture and preview flow.
The current `openFeedbackCapture` returns just after `controller.show`.
Its current future does not mean the flow has ended.
Make that future finish when capture, preview, and send have ended.
Complete it when the user cancels capture.
Mark a submitted capture before calling `controller.hide`.
That hide must not count as capture cancellation.
Also complete it after Send, Keep as draft, or Cancel in preview.
Remove the temporary controller listener when the flow ends.
Restore the tab after completion or failure.
Keep the existing `onResult` callback.

Use this control in the host's current page-wrapper hook.
Remove the fixed footer from that hook.
Keep normal app files free of feedback-package imports.

The control must respect device edges and the keyboard.
Keep a usable touch area and a screen-reader label.
Support English and Serbian.
The control stays hidden in a normal build.

## Options

1. Drawer with an edge tab. Recommended. It keeps the app large and puts both actions in one small panel.
2. Floating button. It also keeps the app large. It covers more of the page while closed.

The owner already prefers a drawer.
The owner approved the right-edge tab design.
Source work can now start.

## Checks

Measure the same host page with and without the control.
Its bounds must match exactly.
Check opening, outside tap, Back, and action ordering.
Check small screens, English, and Serbian.
Check the hidden normal-build control.
Check screenshot capture without the drawer or tab.
Check the report still names the host screen.
Check drafts and sent state after an APK update.
Check the language choice and date fix on a new install.

After source review, build `1.2.8-test`, build `81`.
Keep the same package and signer.
Share a new Tailscale APK link after device checks.
Owner acceptance stays open.
