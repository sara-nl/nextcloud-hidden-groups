<?php

/**
 * SPDX-FileCopyrightText: 2026 Hidden groups contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

declare(strict_types=1);

namespace OCA\HiddenGroups\Collaboration;

use OCA\HiddenGroups\Service\HiddenGroups;
use OCP\Collaboration\Collaborators\ISearchPlugin;
use OCP\Collaboration\Collaborators\ISearchResult;
use OCP\Collaboration\Collaborators\SearchResultType;

/**
 * Removes hidden groups from the search results for sharing and other autocomplete.
 *
 * Core registers its own group plugin before any app plugin, so this runs on the already
 * collected results. Hidden groups are also removed from the exact matches, because sharing
 * with them is not allowed at all. The share itself is refused by RefuseSharingListener.
 */
class HideGroupsPlugin implements ISearchPlugin {
	public function __construct(
		private readonly HiddenGroups $hiddenGroups,
	) {
	}

	/**
	 * Parameters are untyped to match ISearchPlugin::search() on all supported versions.
	 *
	 * @param string $search
	 * @param int $limit
	 * @param int $offset
	 */
	#[\Override]
	public function search($search, $limit, $offset, ISearchResult $searchResult): bool {
		if ($this->hiddenGroups->getGroupIds() === []) {
			return false;
		}

		$groupType = new SearchResultType('groups');
		/** @var array{groups?: list<array{value: array{shareWith: array-key}}>, exact: array{groups?: list<array{value: array{shareWith: array-key}}>}} $results */
		$results = $searchResult->asArray();

		$matches = $results['groups'] ?? [];
		$exactMatches = $results['exact']['groups'] ?? [];
		$visibleMatches = $this->withoutHidden($matches);
		$visibleExactMatches = $this->withoutHidden($exactMatches);
		if (count($visibleMatches) === count($matches) && count($visibleExactMatches) === count($exactMatches)) {
			return false;
		}

		$searchResult->unsetResult($groupType);
		$searchResult->addResultSet($groupType, $visibleMatches, $visibleExactMatches);

		return false;
	}

	/**
	 * @param list<array{value: array{shareWith: array-key}}> $matches
	 * @return list<array{value: array{shareWith: array-key}}>
	 */
	private function withoutHidden(array $matches): array {
		return array_values(array_filter(
			$matches,
			fn (array $match): bool => !$this->hiddenGroups->isHidden((string)$match['value']['shareWith']),
		));
	}
}
