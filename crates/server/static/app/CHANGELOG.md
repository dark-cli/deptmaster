# Web App Changelog

## Latest Changes

### Hide Android Contact URIs
- Phone numbers that are Android contact URIs (starting with `content://`) are now hidden in the browser
- These URIs are only useful in the Android app, not in web browsers
- Regular phone numbers (if any) will still be displayed

### How It Works
The app checks if a phone number starts with `content://` and hides it if it does. This keeps the UI clean and only shows useful information.
