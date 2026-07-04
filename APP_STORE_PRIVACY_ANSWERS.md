# Rocio App Store Privacy Answers Draft

Date: 2026-07-02

Use this as the working draft for App Store Connect App Privacy and App Review notes. Confirm the answers again after any backend provider, analytics, crash reporting, account, sync, or photo upload work is added.

## Current Native iOS Data Behavior

- Rocio stores the user's saved garden locally on the device with `UserDefaults`.
- Rocio can export saved garden data only when the user taps the export control in Settings.
- Rocio can delete saved garden data when the user confirms the destructive delete action in Settings.
- Rocio analyzes camera or photo input locally in the native app for an experimental flower match.
- Rocio does not save scanner photos in the native app.
- Rocio does not send scanner photos, garden data, identifiers, diagnostics, analytics, or contact information to Rocio servers in the current native release.
- Rocio does not enable Plant.id or Supabase provider calls in the current native release.
- Rocio schedules local watering notifications only after the user enables reminders.

## App Privacy Answers

### Data Used To Track The User

No.

Rocio does not use data for third-party advertising, tracking, or data broker sharing.

### Data Linked To The User

None for the current native release.

The app has no account system and does not transmit user data to a backend.

### Data Not Linked To The User

None for the current native release.

Local garden data and selected photos stay on device unless the user manually exports garden data.

### Privacy Manifest

The current privacy manifest declares:

- `NSPrivacyTracking`: false.
- `NSPrivacyCollectedDataTypes`: empty.
- `NSPrivacyAccessedAPITypes`: UserDefaults with reason `CA92.1` for app functionality.

## Permission Explanations

Camera:

Rocio uses the camera only after the user taps `Tomar foto` in the scanner. The photo is analyzed locally on the device to suggest possible flower matches.

Photos:

Rocio uses only photos the user selects through the system photo picker. Selected images are analyzed locally and are not stored by the app in this native release.

Notifications:

Rocio asks for notification permission only from Settings when the user taps `Activar recordatorios de riego`. Notifications are local watering reminders based on saved garden plants.

## Review Notes Draft

Rocio is a Spanish-first flower-care app. The native iOS app stores the user's garden locally on the device, schedules local watering reminders after user opt-in, and offers an experimental local flower identification helper using camera or photo input. Identification is assistive and may be uncertain; the app does not claim professional botanical, agricultural, or medical accuracy.

No Plant.id or Supabase provider calls are enabled in the current native iOS release. Camera and selected photo input are analyzed locally on the device and are not uploaded or saved by the app.

## Still Required Before External TestFlight Or Submission

- Publish a privacy policy URL that matches this draft.
- Publish a support URL.
- Recheck App Privacy answers after Xcode build validation and before upload.
- Update this draft if any analytics, crash reporting, sync, account, Supabase, Plant.id, or image upload behavior is introduced.
