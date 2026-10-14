<!--
  - SPDX-FileCopyrightText: 2026 Hidden groups contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->
# Hidden groups for Nextcloud

Some groups are only meant for configuration, such as enabling an app for everyone, and are far too large to share with.
When someone shares with such a group by accident, a lot of people get access and the server has a lot of work to do.

With this app, admins can hide such groups under Administration → Sharing → Hidden groups.

- Nobody can share files or folders with a hidden group, whichever way the share is created, also through the API.
  People get the message "Sharing with this group is not allowed."
- Hidden groups do not show up in sharing suggestions, not even when someone types their exact name.
  This also applies to other places that use the Nextcloud autocomplete, such as adding participants in Talk.
- Existing shares with a hidden group keep working. They can still be renamed, moved and transferred to another owner,
  but cannot get more permissions.

Supported Nextcloud versions: 34.0.2 – 35.

### Technically

The hidden groups are stored in the app config:

```
sudo -u www-data php occ config:app:set hidden_groups groups --value '["<GroupID>"]' --type array
```

If the value was stored with another type, no group is hidden and an error is logged.
Saving the hidden groups in the admin settings fixes it, or delete it and set it again:

```
sudo -u www-data php occ config:app:delete hidden_groups groups
```

The app registers a collaborator search plugin (see `appinfo/info.xml`) that runs after the Nextcloud group search
and removes hidden groups from the results.

Shares are refused through the Nextcloud interaction API (`RestrictInteractionEvent`).
Nextcloud also checks this when it updates existing shares, for example after a rename,
so those updates are allowed as long as they do not add permissions.
Group ids are compared without trailing spaces and case, because MySQL and MariaDB find a group even with a trailing space.

### Limits

- The share dialog suggests recipients you shared with before, before you type anything. A hidden group can still show up there,
  but sharing with it is refused.
- Calendars and address books can still be shared with a hidden group, as they are not shared through the files sharing API.
- A hidden group can still be reached through a team, Talk conversation or Deck board that contains it.
  To stop groups from being added to teams, see the `allowed_types` setting of the Teams (circles) app.

### Translations

The app is translated into Dutch, German (informal and formal), French and Spanish.
The translations are kept in `translationfiles/<language>/hidden_groups.po`, Nextcloud reads the generated files in `l10n/`.
After changing texts, update them with the [translation tool](https://github.com/nextcloud/docker-ci/tree/master/translations/translationtool):

```
php translationtool.phar create-pot-files
msgmerge --update translationfiles/nl/hidden_groups.po translationfiles/templates/hidden_groups.pot
# translate the new or changed texts, for example with Poedit, for every language
php translationtool.phar convert-po-files
```

### Releasing

Releases are published to the [Nextcloud App Store](https://apps.nextcloud.com/apps/hidden_groups) by the Release workflow:

1. Set the new version in `appinfo/info.xml` and `package.json`, and describe the changes in `CHANGELOG.md`.
2. Merge to `main` and check that the tests are green.
3. Publish a GitHub release with the tag `v<version>`, for example `v1.0.1`, and approve the `appstore` deployment
   within 30 days. After that the built app has expired and the workflow has to be run again.

The workflow builds the app in a job without secrets. A second job signs it with the app's code signing certificate,
attaches the tarball to the GitHub release and publishes it to the App Store.

- A pre-release is signed and attached, but not published to the App Store. To publish it later, remove the tarball
  from the release, turn the release into a draft, untick "Set as a pre-release" and publish it again.
  Only unticking it does not start the workflow.
- If a run fails after the tarball was attached, re-run the failed jobs: the attached tarball is reused, not replaced,
  so a signature the App Store already has stays valid.
- A tarball that was attached by hand, or by another run, is never signed or published. The workflow stops then:
  remove the tarball from the release and re-run the workflow.
- Keep "immutable releases" off in the repository settings, because the tarball is attached after the release was published.

#### One-time setup

1. Request the code signing certificate for `hidden_groups` at [nextcloud/app-certificate-requests](https://github.com/nextcloud/app-certificate-requests),
   and keep `hidden_groups.key` safe outside the repository.
2. Register the app on the [App Store](https://apps.nextcloud.com/developer/apps/new) with the certificate and a signature of the app id:
   `echo -n "hidden_groups" | openssl dgst -sha512 -sign hidden_groups.key | openssl base64`.
   Then create an API token in your App Store account.
3. In the GitHub repository, create the environment `appstore` (Settings → Environments). Add required reviewers,
   limit its deployment tags to `v*`, and add these secrets to it:
   - `APP_PRIVATE_KEY`: the private key of the code signing certificate (`hidden_groups.key`)
   - `APP_PUBLIC_CRT`: the certificate Nextcloud issued for it (`hidden_groups.crt`)
   - `APPSTORE_TOKEN`: the API token of the App Store account that owns the app
4. Protect the release tags with a tag ruleset for `v*` (Settings → Rules → Rulesets), so only maintainers can create them.
   The workflow that runs is the one in the tagged commit, so the tag decides which code gets the signing key.

To build a release by hand:

```
npm ci && npm run build
make buildapp version=1.0.1
```

The tarball is then in `build/artifacts/app/`. It still has to be signed with `occ integrity:sign-app`.

The app has no runtime Composer dependencies, so `vendor/` is not part of the release.
Composer is only needed for the development tooling: `composer install`, then `composer psalm` and `composer cs:check`.

### Tests

The tests run against a real Nextcloud, using the official Docker image:

```
npm ci && npm run build
make test nc=35
```

`tests/e2e/e2e.sh` can also run against an existing test server over SSH, see the comment at the top of the script.
GitHub Actions runs the tests on Nextcloud 34 and 35 for every pull request, and monthly against the newest Nextcloud release. The monthly run also checks the code with psalm against the API of the next Nextcloud version.
