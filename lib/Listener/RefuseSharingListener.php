<?php

declare(strict_types=1);

namespace OCA\HiddenGroups\Listener;

use OCA\HiddenGroups\Service\HiddenGroups;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\IDBConnection;
use OCP\IL10N;
use OCP\Interaction\Actions\ShareAction;
use OCP\Interaction\InteractionResource;
use OCP\Interaction\InteractionRestrictedException;
use OCP\Interaction\Receivers\GroupReceiver;
use OCP\Interaction\Resources\NodeResource;
use OCP\Interaction\RestrictInteractionEvent;
use OCP\Share\IShare;

/**
 * Refuses new shares with hidden groups, whichever way the share is created.
 *
 * Nextcloud runs the same check when it updates an existing share, for example when a shared
 * folder is renamed, moved or transferred to another owner. Existing shares with a hidden group
 * keep working, so those updates are allowed as long as they do not add permissions.
 *
 * @template-implements IEventListener<Event|RestrictInteractionEvent>
 */
class RefuseSharingListener implements IEventListener {
	public function __construct(
		private readonly HiddenGroups $hiddenGroups,
		private readonly IDBConnection $db,
		private readonly IL10N $l10n,
	) {
	}

	#[\Override]
	public function handle(Event $event): void {
		if (!$event instanceof RestrictInteractionEvent || !$event->action instanceof ShareAction) {
			return;
		}

		foreach ($event->receivers as $receiver) {
			if (!$receiver instanceof GroupReceiver || !$this->hiddenGroups->isHidden($receiver->groupId)) {
				continue;
			}
			if ($this->isExistingShare($receiver->groupId, $event->resources, $event->action->filesSharingPermissions)) {
				continue;
			}
			throw new InteractionRestrictedException(
				'Sharing with group ' . $receiver->groupId . ' is refused, an admin has hidden it.',
				$this->l10n->t('Sharing with this group is not allowed.'),
			);
		}
	}

	/**
	 * Whether the group already has a share on the node with at least these permissions.
	 *
	 * @param list<InteractionResource> $resources
	 */
	private function isExistingShare(string $groupId, array $resources, ?int $permissions): bool {
		$nodeIds = [];
		foreach ($resources as $resource) {
			if ($resource instanceof NodeResource) {
				$nodeIds[] = $resource->nodeId;
			}
		}
		if ($nodeIds === []) {
			return false;
		}

		$qb = $this->db->getQueryBuilder();
		$qb->select('share_with', 'permissions')
			->from('share')
			->where($qb->expr()->eq('share_type', $qb->createNamedParameter(IShare::TYPE_GROUP, IQueryBuilder::PARAM_INT)))
			->andWhere($qb->expr()->eq('share_with', $qb->createNamedParameter($groupId)))
			->andWhere($qb->expr()->in('file_source', $qb->createNamedParameter($nodeIds, IQueryBuilder::PARAM_INT_ARRAY)));
		$result = $qb->executeQuery();

		$existingPermissions = null;
		while ($row = $result->fetch()) {
			// Compare again here, MySQL and MariaDB ignore trailing spaces
			if ($row['share_with'] === $groupId) {
				$existingPermissions = ($existingPermissions ?? 0) | (int)$row['permissions'];
			}
		}
		$result->closeCursor();

		if ($existingPermissions === null) {
			return false;
		}
		return $permissions === null || ($permissions & ~$existingPermissions) === 0;
	}
}
