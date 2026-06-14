# NodeQL Privacy

NodeQL is local-first. Projects, settings, installed plugins, cached language
packages, and database paths are stored on the user's device.

NodeQL does not include advertising, analytics, account tracking, or automatic
crash reporting.

The application can make these outbound HTTPS requests:

- GitHub Releases API requests to check for a newer NodeQL release.
- Public GitHub Pages or raw GitHub requests when the user refreshes or
  installs community language packages.
- Links explicitly opened by the user in an external browser.

Database contents and project files are not uploaded by these features.
Network access can be blocked without disabling local project editing or
cached translations.

Third-party plugin manifests are installed from files selected by the user.
Plugin API v1 is declarative and does not execute third-party Dart or native
code.
