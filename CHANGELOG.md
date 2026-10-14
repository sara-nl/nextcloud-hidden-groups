<!--
  - SPDX-FileCopyrightText: 2026 Hidden groups contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->
# Changelog

All notable changes to this app are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.0.1 - 2026-10-14

First release on the Nextcloud App Store.

### Added

- Screenshots for the App Store.

### Changed

- Licence and copyright information in the REUSE format. The licence texts are in `LICENSES/`.

## 1.0.0 - 2026-10-12

### Added

- Admins can hide groups under Administration → Sharing → Hidden groups.
- Nobody can share files or folders with a hidden group, also not through the API.
- Hidden groups do not show up in sharing suggestions, not even when someone types their exact name.
- Existing shares with a hidden group keep working. They can still be renamed, moved and transferred, but cannot get more permissions.
- Translations for Dutch, German (informal and formal), French and Spanish.
