# BloggerApp

A native iOS client for [Blogger](https://www.blogger.com) — write, edit and publish posts and pages on the go. Built with SwiftUI and the official [Blogger API v3](https://developers.google.com/blogger/docs/3.0/reference).

## Features

- **Google Sign-In** — OAuth 2.0 via `GoogleSignIn`; refresh-token persistence in the Keychain
- **Post editor** — WYSIWYG editing powered by **TipTap (ProseMirror)** inside a `WKWebView`, with:
  - Cursor-traced floating formatting toolbar (bold, italic, headings, lists, alignment, links, …)
  - HTML source view toggle and rendered preview
  - Image insertion with an uploading placeholder + spinner (hosted via Google Photos)
- **Page editor** — same rich editing capabilities for static pages
- **Post & page lists** — Published / Drafts / Local tabs, pull-to-refresh, infinite scroll (`pageToken` pagination)
- **Local drafts** — unsaved edits auto-save locally and survive app relaunch
- **Labels** — apply/remove post labels
- **Comments** — view and manage post comments
- **Stats** — page-view statistics per blog
- **Blog switcher** — manage multiple blogs and accounts

## Requirements

- iOS 17.0+
- Xcode 16+
- A Google Cloud project with the **Blogger API** and **Photos Library API** enabled

## Setup

1. Open `BloggerApp.xcodeproj` in Xcode.
2. In `BloggerApp/Configuration.swift`, replace `googleClientID` with your own OAuth 2.0 iOS client ID from the [Google Cloud Console](https://console.cloud.google.com/apis/credentials). The URL scheme (`googleURLScheme`) is derived automatically.
3. Add the derived URL scheme (`com.googleusercontent.apps.<client-id>`) to the app's `Info.plist` under `CFBundleURLTypes`.
4. Select your development team in the target's Signing settings (bundle ID: `studio.evol.blogger.app`).
5. Build and run.

### Requested OAuth scopes

Defined in `Configuration.scopes`:

- `https://www.googleapis.com/auth/blogger`
- `https://www.googleapis.com/auth/photoslibrary.appendonly`
- `https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata`

> Note: since March 2025 the Photos Library API only exposes app-created media via `readonly.appcreateddata`. Also, Google Photos `baseUrl`s expire after 60 minutes — image URLs embedded via the upload flow are short-lived (see `GooglePhotosUploader` for details).

## Architecture

```
BloggerApp/
├── AppState.swift          # App-wide state (auth, API client, drafts)
├── Auth/                   # GoogleSignIn wrapper + Keychain token store
├── Networking/             # BloggerClient (Blogger API v3), errors
├── Models/                 # Post, Page, Comment, Blog, PageViews, …
├── Persistence/            # LocalDraftStore (JSON file-backed drafts)
├── Images/                 # ImageUploading protocol + GooglePhotosUploader
├── Editor/                 # TipTap WKWebView bridge (RichEditorView)
├── Resources/Editor/       # editor.html + bundled tiptap.js
└── Views/                  # SwiftUI screens
```

### The editor

The rich editor is TipTap v3 bundled into a single IIFE (`Resources/Editor/tiptap.js`) and loaded by `editor.html` in a `WKWebView`. Swift communicates over a script-message bridge:

- `setHTML` / `getHTML` — content sync through the `html` binding
- `insertImage` — inserts an `<img>` at the cursor
- Formatting commands (`bold`, `heading`, `bulletList`, `setLink`, …)
- Height/state callbacks for layout and toolbar sync

Rebuild the JS bundle with [esbuild](https://esbuild.github.io/) from the TipTap sources if you need to change editor behaviour.

## Not implemented / limitations

- Image upload depends on Google Photos, whose base URLs expire (60 min) — not suited for permanent inline images in published posts.
- `xcodebuild test` on Xcode 16 has a known simulator test-host quirk; the `BloggerAppTests` target exists but may not run headlessly.

## License

Homework project — no license specified.
