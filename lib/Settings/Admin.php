<?php

/**
 * SPDX-FileCopyrightText: 2026 Hidden groups contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

declare(strict_types=1);

namespace OCA\HiddenGroups\Settings;

use OCA\HiddenGroups\AppInfo\Application;
use OCA\HiddenGroups\Service\HiddenGroups;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\AppFramework\Services\IInitialState;
use OCP\Settings\ISettings;
use OCP\Util;

class Admin implements ISettings {
	public function __construct(
		private readonly IInitialState $initialState,
		private readonly HiddenGroups $hiddenGroups,
	) {
	}

	#[\Override]
	public function getForm(): TemplateResponse {
		$this->initialState->provideInitialState(Application::GROUPS_KEY, $this->hiddenGroups->getGroupIds());

		Util::addScript(Application::APP_ID, 'hidden_groups-main');
		Util::addStyle(Application::APP_ID, 'hidden_groups-main');

		return new TemplateResponse(Application::APP_ID, 'settings-admin');
	}

	#[\Override]
	public function getSection(): string {
		return 'sharing';
	}

	#[\Override]
	public function getPriority(): int {
		return 90;
	}
}
