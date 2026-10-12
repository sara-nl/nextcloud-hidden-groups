/**
 * SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import path from 'path'
import { fileURLToPath } from 'url'
import { createAppConfig } from '@nextcloud/vite-config'

// Fix __dirname in ESM
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

export default createAppConfig(
  {
    main: path.join(__dirname, 'src', 'main.js'),
  },
  {
    inlineCSS: false
  }
)
