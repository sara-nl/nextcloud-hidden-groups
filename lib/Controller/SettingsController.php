<?php

declare(strict_types=1);

namespace OCA\HiddenGroups\Controller;

use OCA\HiddenGroups\Service\HiddenGroups;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\FrontpageRoute;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;

/**
 * Admin only, as none of the methods have the NoAdminRequired attribute.
 */
class SettingsController extends Controller {
	public function __construct(
		string $appName,
		IRequest $request,
		private readonly HiddenGroups $hiddenGroups,
	) {
		parent::__construct($appName, $request);
	}

	/**
	 * @param array<array-key, mixed> $groups
	 */
	#[FrontpageRoute(verb: 'PUT', url: '/settings/groups')]
	public function setGroups(array $groups = []): JSONResponse {
		return new JSONResponse([
			'groups' => $this->hiddenGroups->setGroupIds($groups),
		]);
	}
}
