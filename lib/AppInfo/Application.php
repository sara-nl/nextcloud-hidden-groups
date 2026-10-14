<?php

/**
 * SPDX-FileCopyrightText: 2026 Hidden groups contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

declare(strict_types=1);

namespace OCA\HiddenGroups\AppInfo;

use OCA\HiddenGroups\Config\ConfigLexicon;
use OCA\HiddenGroups\Listener\RefuseSharingListener;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\Interaction\RestrictInteractionEvent;

class Application extends App implements IBootstrap {
	public const APP_ID = 'hidden_groups';

	public const GROUPS_KEY = 'groups';

	public function __construct() {
		parent::__construct(self::APP_ID);
	}

	#[\Override]
	public function register(IRegistrationContext $context): void {
		// The collaborator search plugin is registered in appinfo/info.xml
		$context->registerConfigLexicon(ConfigLexicon::class);
		$context->registerEventListener(RestrictInteractionEvent::class, RefuseSharingListener::class);
	}

	#[\Override]
	public function boot(IBootContext $context): void {
	}
}
