<!--
  - SPDX-FileCopyrightText: 2026 Hidden groups contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->
<template>
	<NcSettingsSection
		:name="t('hidden_groups', 'Hidden groups')"
		:description="t('hidden_groups', 'Nobody can share files or folders with these groups, and they do not show up in suggestions, for example in the share dialog. Use this for large groups that are only meant for configuration, such as enabling an app for everyone. Existing shares keep working, but cannot get more permissions. Calendars, address books and teams that contain such a group are not covered.')">
		<NcSettingsSelectGroup
			:modelValue="hiddenGroups"
			:label="t('hidden_groups', 'Groups that nobody can share with')"
			@update:modelValue="saveHiddenGroups" />
	</NcSettingsSection>
</template>

<script setup>
import axios from '@nextcloud/axios'
import { showError, showSuccess } from '@nextcloud/dialogs'
import { loadState } from '@nextcloud/initial-state'
import { t } from '@nextcloud/l10n'
import { generateUrl } from '@nextcloud/router'
import { ref } from 'vue'
import NcSettingsSection from '@nextcloud/vue/components/NcSettingsSection'
import NcSettingsSelectGroup from '@nextcloud/vue/components/NcSettingsSelectGroup'

const hiddenGroups = ref(loadState('hidden_groups', 'groups', []))

// Saves run one after the other, so the server always ends up with the last selection
let savedGroups = hiddenGroups.value
let queue = Promise.resolve()
let latestSave = 0

/**
 * Store the new list of hidden groups. If that fails, show the list that is stored on the server.
 *
 * @param {string[]} groups the ids of the hidden groups
 */
function saveHiddenGroups(groups) {
	hiddenGroups.value = groups
	const save = ++latestSave

	queue = queue.then(async () => {
		try {
			const { data } = await axios.put(generateUrl('/apps/hidden_groups/settings/groups'), { groups })
			savedGroups = data.groups
			if (save === latestSave) {
				hiddenGroups.value = data.groups
				showSuccess(t('hidden_groups', 'Hidden groups saved'))
			}
		} catch {
			if (save === latestSave) {
				hiddenGroups.value = savedGroups
			}
			showError(t('hidden_groups', 'Failed to save the hidden groups'))
		}
	})
}
</script>
