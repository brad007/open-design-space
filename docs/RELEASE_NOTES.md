An open-source, offline-first design app for cutting machines. Early alpha:
the design tools and exports are tested, but output hasn't been checked on
real cutting machines yet.

## Download

| Platform | File |
| --- | --- |
| Windows 10/11 (64-bit) | `OpenDesignSpace-…-windows-x64.zip` |
| macOS 11+ (Apple silicon and Intel) | `OpenDesignSpace-…-macos.zip` |
| Linux (64-bit) | `OpenDesignSpace-…-linux-x64.tar.gz` |
| Android 7+ | `OpenDesignSpace-…-android.apk` |
| Web (self-host) | `OpenDesignSpace-…-web.zip` |

These builds aren't signed with a paid developer certificate, so each system
warns you the first time. That's expected for a new open-source app.

### Windows
1. Unzip the file anywhere, for example into `Documents\Open Design Space`.
2. Run `open_design_space.exe`.
3. If SmartScreen says "Windows protected your PC", click **More info → Run anyway**.

### macOS
1. Unzip and drag **Open Design Space** into Applications.
2. The first time, right-click the app and choose **Open**, then **Open** again.
   If macOS says the app is damaged, run this once in Terminal:
   `xattr -dr com.apple.quarantine "/Applications/Open Design Space.app"`

### Linux
1. Extract: `mkdir open-design-space && tar -xzf OpenDesignSpace-*-linux-x64.tar.gz -C open-design-space`
2. Run `./open-design-space/open_design_space`. It needs GTK 3, which most
   desktops already have. File dialogs use `zenity`.

### Android
1. Download the `.apk` on your phone or tablet and open it.
2. Allow installing from your browser or file manager when asked.
   Play Protect may warn about an unknown app; choose **Install anyway**.

### Web
Unzip and serve the folder from any static web host. Projects are kept in
memory only, so export your work before closing the tab.

### iPhone and iPad
There's no download for iOS yet: Apple only allows installing apps signed
through a developer account. You can build it yourself with
`flutter run -d ios` from the source code.
