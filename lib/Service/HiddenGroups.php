<?php

declare(strict_types=1);

namespace OCA\HiddenGroups\Service;

use OCA\HiddenGroups\AppInfo\Application;
use OCP\Exceptions\AppConfigException;
use OCP\Exceptions\AppConfigTypeConflictException;
use OCP\IAppConfig;
use Psr\Log\LoggerInterface;

/**
 * The groups an admin has hidden from sharing.
 */
class HiddenGroups {
	public function __construct(
		private readonly IAppConfig $appConfig,
		private readonly LoggerInterface $logger,
	) {
	}

	/**
	 * @return list<string>
	 */
	public function getGroupIds(): array {
		try {
			$groupIds = $this->appConfig->getValueArray(Application::APP_ID, Application::GROUPS_KEY);
		} catch (AppConfigException $e) {
			// Keep sharing working for everyone, and make sure an admin can find out why nothing is hidden
			$this->logger->error('The hidden groups cannot be read, so no group is hidden. Save them again in the admin settings, or run occ config:app:delete hidden_groups groups and set them again.', [
				'app' => Application::APP_ID,
				'exception' => $e,
			]);
			return [];
		}
		return self::clean($groupIds);
	}

	public function isHidden(string $groupId): bool {
		$groupId = self::normalize($groupId);
		foreach ($this->getGroupIds() as $hiddenGroupId) {
			if (self::normalize($hiddenGroupId) === $groupId) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @param array<array-key, mixed> $groupIds
	 * @return list<string> the stored group ids
	 */
	public function setGroupIds(array $groupIds): array {
		$groupIds = self::clean($groupIds);
		try {
			$this->appConfig->setValueArray(Application::APP_ID, Application::GROUPS_KEY, $groupIds);
		} catch (AppConfigTypeConflictException) {
			// Stored with another type, for example through occ with another --type
			$this->appConfig->deleteKey(Application::APP_ID, Application::GROUPS_KEY);
			$this->appConfig->setValueArray(Application::APP_ID, Application::GROUPS_KEY, $groupIds);
		}
		return $groupIds;
	}

	/**
	 * @param array<array-key, mixed> $groupIds
	 * @return list<string>
	 */
	private static function clean(array $groupIds): array {
		$groupIds = array_filter($groupIds, static fn (mixed $groupId): bool => is_string($groupId) && trim($groupId) !== '');
		return array_values(array_unique($groupIds));
	}

	/**
	 * Core passes group ids exactly as the user typed them. MySQL and MariaDB ignore trailing spaces
	 * when they look up the group, and some group backends ignore case, so compare without both.
	 */
	private static function normalize(string $groupId): string {
		return mb_strtolower(rtrim($groupId));
	}
}
