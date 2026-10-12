#!/usr/bin/env bash
# End-to-end test against a running Nextcloud with this app enabled.
#
# usage: tests/e2e/e2e.sh <base_url> docker <container>
#        E2E_PW=<password> tests/e2e/e2e.sh <base_url> ssh <user@host> <nextcloud_path>
#
# Creates the users hgtestalice, hgtesthenk and hgtestpiet in the group hgtest, the group
# hgtestbig with henk as member, and a temporary admin hgtestadmin that is always deleted again.
# Checks the share dialog search, core autocomplete, creating, changing, moving and transferring
# shares, and the admin settings page.
# In ssh mode E2E_PW is required, because the test users would otherwise get a password that
# is public in this repository. Set E2E_CLEANUP=1 to also delete the other test users and groups.
# Needs curl and python3.
set -uo pipefail
BASE=$1; MODE=$2; shift 2
if [ "$MODE" = docker ]; then CONTAINER=$1; else HOST=$1; NCPATH=$2; fi

if [ "$MODE" = ssh ] && [ -z "${E2E_PW:-}" ]; then
	echo "Set E2E_PW to a password of your own when testing a server over ssh." >&2
	exit 2
fi
PW=${E2E_PW:-'Hg-e2e-Pw-2026-Kx4!'}
A=hgtestalice; B=hgtesthenk; C=hgtestpiet; ADM=hgtestadmin; G=hgtest; BG=hgtestbig
SHARE_PATH=/hgtest-share
pass=0; fail=0

occ() {
	if [ "$MODE" = docker ]; then
		docker exec -e OC_PASS="$PW" -u www-data "$CONTAINER" php occ "$@"
	else
		ssh -o BatchMode=yes "$HOST" "sudo -n -u www-data env OC_PASS=$(printf '%q' "$PW") php $NCPATH/occ $(printf '%q ' "$@")"
	fi
}
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1 (expected '$3', got '$2')"; fail=$((fail+1)); fi; }
# yes/no whether a comma separated list contains an id, or "error" when the request failed
has() { if [[ "$1" == ERROR* ]]; then echo error; elif [[ ",$1," == *",$2,"* ]]; then echo yes; else echo no; fi; }

# GET an OCS endpoint as <user>, prints the response body or ERROR when the request failed
ocs_get() {
	curl -s -u "$1:$PW" -H 'OCS-APIRequest: true' -w '\n%{http_code}' "$BASE/ocs/v2.php/$2" |
		python3 -c 'import json,sys
body, status = sys.stdin.read().rsplit("\n", 1)
try:
    if status != "200" or json.loads(body)["ocs"]["meta"]["statuscode"] != 200:
        raise ValueError
    print(body)
except Exception:
    print("ERROR " + status)'
}

# Share dialog search as alice, prints "<groups>|<exact groups>"
sharees() {
	ocs_get $A "apps/files_sharing/api/v1/sharees?search=$1&itemType=file&perPage=50&format=json" |
		python3 -c 'import json,sys
body = sys.stdin.read()
if body.startswith("ERROR"):
    print("|".join([body.strip()] * 2)); sys.exit()
d = json.loads(body)["ocs"]["data"]
ids = lambda matches: ",".join(sorted(str(m["value"]["shareWith"]) for m in matches))
print(ids(d.get("groups", [])) + "|" + ids(d.get("exact", {}).get("groups", [])))'
}
group_matches() { sharees "$1" | cut -d'|' -f1; }
exact_group_matches() { sharees "$1" | cut -d'|' -f2; }

# Core autocomplete for groups as alice, used for example by Talk to add participants
autocomplete_groups() {
	ocs_get $A "core/autocomplete/get?search=$1&itemType=files&itemId=1&shareTypes%5B%5D=1&limit=20&format=json" |
		python3 -c 'import json,sys
body = sys.stdin.read()
print(body.strip() if body.startswith("ERROR") else ",".join(sorted(m["id"] for m in json.loads(body)["ocs"]["data"])))'
}

# Share API as $SHARER (alice unless set), prints "<http status>|<ocs message>|<share id>"
SHARER=$A
shares_api() {
	local method=$1 path=$2
	shift 2
	curl -s -u "$SHARER:$PW" -H 'OCS-APIRequest: true' -X "$method" "$@" -w '\n%{http_code}' \
		"$BASE/ocs/v2.php/apps/files_sharing/api/v1/$path" |
		python3 -c 'import json,sys
body, status = sys.stdin.read().rsplit("\n", 1)
try:
    ocs = json.loads(body)["ocs"]
    data = ocs.get("data")
    share_id = data.get("id", "") if isinstance(data, dict) else ""
    print(status + "|" + (ocs["meta"].get("message") or "") + "|" + str(share_id))
except Exception:
    print(status + "||")'
}
share_with_group() { shares_api POST "shares?format=json" -d "path=$SHARE_PATH" -d shareType=1 --data-urlencode "shareWith=$1" -d "permissions=${2:-1}"; }
change_share() { shares_api PUT "shares/$1?format=json" -d "permissions=$2"; }
delete_share() { shares_api DELETE "shares/$1?format=json" >/dev/null; }
delete_all_shares() { # of $SHARER
	local ids
	ids=$(curl -s -u "$SHARER:$PW" -H 'OCS-APIRequest: true' "$BASE/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" |
		python3 -c 'import json,sys
try: print(" ".join(str(share["id"]) for share in json.load(sys.stdin)["ocs"]["data"]))
except Exception: pass')
	for id in $ids; do delete_share "$id"; done
}
group_share_id() { # id of the share of $SHARER with <group>
	curl -s -u "$SHARER:$PW" -H 'OCS-APIRequest: true' "$BASE/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" |
		python3 -c 'import json,sys
print(next((str(s["id"]) for s in json.load(sys.stdin)["ocs"]["data"] if s["share_type"] == 1 and s["share_with"] == sys.argv[1]), "none"))' "$1"
}
refusal_in() {
	case $1 in
		nl) echo 'Delen met deze groep is niet toegestaan.' ;;
		de | de_DE) echo 'Teilen mit dieser Gruppe ist nicht erlaubt.' ;;
		fr) echo 'Le partage avec ce groupe n’est pas autorisé.' ;;
		es) echo 'No está permitido compartir con este grupo.' ;;
	esac
}
status() { cut -d'|' -f1; }
status_and_message() { cut -d'|' -f1,2; }
refused() { local s; s=$(status); [ "$s" != 200 ] && [ -n "$s" ] && echo refused || echo "allowed ($s)"; }

# WebDAV as <user>
dav() { # <user> <method> <path> [curl args...] -> http status
	local user=$1 method=$2 path=$3
	shift 3
	curl -s -o /dev/null -w '%{http_code}' -u "$user:$PW" -X "$method" "$@" "$BASE/remote.php/dav/files/$user$path"
}
dav_move() { dav "$1" MOVE "$2" -H "Destination: $BASE/remote.php/dav/files/$1$3"; }
dav_get() { curl -s -u "$1:$PW" "$BASE/remote.php/dav/files/$1$2"; }
delete_transferred_folders() { # of piet, from earlier runs
	local hrefs
	hrefs=$(curl -s -u "$C:$PW" -X PROPFIND -H 'Depth: 1' "$BASE/remote.php/dav/files/$C/" |
		python3 -c 'import re,sys
print("\n".join(h for h in re.findall(r"<d:href>([^<]*)</d:href>", sys.stdin.read()) if "transferred" in h))')
	while read -r href; do
		[ -n "$href" ] && curl -s -o /dev/null -u "$C:$PW" -X DELETE "${BASE%%/}${href}"
	done <<< "$hrefs"
}

# Requests to the settings controller and page are done as $ME
as_user() { ME=$1; }
set_hidden_groups() {
	curl -s -u "$ME:$PW" -H 'OCS-APIRequest: true' -X PUT -H 'Content-Type: application/json' \
		-d "{\"groups\": $1}" -w ' %{http_code}' "$BASE/index.php/apps/hidden_groups/settings/groups"
}
admin_page() { curl -s -u "$ME:$PW" "$BASE/index.php/settings/admin/sharing"; }
initial_state() { admin_page | grep -o 'id="initial-state-hidden_groups-groups" value="[^"]*"' | cut -d'"' -f4 | base64 -d 2>/dev/null; }
script_status() { # <script name> [extension]
	local src
	src=$(admin_page | grep -o "src=\"[^\"]*hidden_groups[^\"]*$1\.${2:-mjs}[^\"]*\"" | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
	[ -n "$src" ] && curl -s -o /dev/null -w '%{http_code}' -u "$ME:$PW" "$BASE$src" || echo "no script tag"
}

# --- setup ---------------------------------------------------------------
cleanup_admin() { occ user:delete $ADM >/dev/null 2>&1; }
trap cleanup_admin EXIT

occ group:add $G >/dev/null 2>&1
occ group:add $BG >/dev/null 2>&1
for u in $A $B $C; do
	occ user:add --password-from-env --display-name="$u" --group=$G $u >/dev/null 2>&1 || occ user:resetpassword --password-from-env $u >/dev/null
done
occ group:adduser $BG $B >/dev/null 2>&1
occ user:add --password-from-env --display-name="$ADM" --group=admin $ADM >/dev/null 2>&1 || occ user:resetpassword --password-from-env $ADM >/dev/null
occ config:app:delete hidden_groups groups >/dev/null 2>&1
for SHARER in $A $C; do delete_all_shares; done
SHARER=$A
delete_transferred_folders
dav $A DELETE /hgtest-parent2 >/dev/null
dav $A MKCOL $SHARE_PATH >/dev/null
dav $A PUT "$SHARE_PATH/hello.txt" --data-binary 'hello' >/dev/null

echo "== $(occ status --output=json | python3 -c 'import json,sys; print("Nextcloud", json.load(sys.stdin)["versionstring"])')"

# --- baseline ------------------------------------------------------------
check "baseline: big group in share suggestions"             "$(has "$(group_matches hgtestbi)" $BG)" yes
check "baseline: big group in core autocomplete"             "$(has "$(autocomplete_groups hgtestbi)" $BG)" yes
existing=$(share_with_group $BG 31)
check "baseline: alice shares a folder with the big group"   "$(echo "$existing" | status)" 200
existing_id=$(echo "$existing" | cut -d'|' -f3)
check "baseline: big group member reads the shared file"     "$(dav_get $B "$SHARE_PATH/hello.txt")" hello

# --- admin settings ------------------------------------------------------
as_user $A
check "users cannot change the hidden groups"                "$(set_hidden_groups "[\"$BG\"]" | awk '{print $NF}')" 403
as_user $ADM
check "admin page loads the app script"                      "$(script_status hidden_groups-main)" 200
occ user:setting $ADM core lang nl >/dev/null
check "admin page loads the Dutch translations"              "$(script_status 'l10n/nl' js)" 200
occ user:setting $ADM core lang --delete >/dev/null
check "admin page shows no hidden groups"                    "$(initial_state)" '[]'
check "admin hides the big group"                            "$(set_hidden_groups "[\"$BG\", \"$BG\", 3, \"\"]")" "{\"groups\":[\"$BG\"]} 200"
check "admin page shows the hidden group"                    "$(initial_state)" "[\"$BG\"]"

# --- hidden in suggestions -----------------------------------------------
check "hidden group not in share suggestions"                "$(has "$(group_matches hgtestbi)" $BG)" no
check "hidden group not found by its exact name"             "$(has "$(exact_group_matches $BG)" $BG)" no
check "other groups still in share suggestions"              "$(has "$(exact_group_matches hgtest)" $G)" yes
check "hidden group not in core autocomplete"                "$(has "$(autocomplete_groups hgtestbi)" $BG)" no

# --- new shares are refused ------------------------------------------------
dav $A MKCOL /hgtest-other >/dev/null
SHARE_PATH=/hgtest-other
check "a new share with the hidden group is refused"         "$(share_with_group $BG | status_and_message)" '403|Sharing with this group is not allowed.'
check "a padded group name is refused"                       "$(share_with_group "$BG " | refused)" refused
check "a group name in other case is refused"                "$(share_with_group "$(echo $BG | tr a-z A-Z)" | refused)" refused
for lang in nl de de_DE fr es; do
	occ user:setting $A core lang $lang >/dev/null
	check "the refusal is translated ($lang)"                 "$(share_with_group $BG | cut -d'|' -f2)" "$(refusal_in $lang)"
done
occ user:setting $A core lang --delete >/dev/null
other=$(share_with_group $G)
check "sharing with other groups still works"                "$(echo "$other" | status)" 200
delete_share "$(echo "$other" | cut -d'|' -f3)"
SHARE_PATH=/hgtest-share

# --- existing shares keep working ------------------------------------------
check "an existing share can get fewer permissions"          "$(change_share "$existing_id" 1 | status)" 200
check "an existing share cannot get more permissions"        "$(change_share "$existing_id" 31 | status_and_message)" '403|Sharing with this group is not allowed.'

check "the shared folder can be renamed"                     "$(dav_move $A $SHARE_PATH /hgtest-renamed)" 201
dav $A MKCOL /hgtest-parent >/dev/null
check "the shared folder can be moved into a folder"         "$(dav_move $A /hgtest-renamed /hgtest-parent/hgtest-renamed)" 201
check "the folder above it can be renamed"                   "$(dav_move $A /hgtest-parent /hgtest-parent2)" 201
check "the shared folder can be moved back"                  "$(dav_move $A /hgtest-parent2/hgtest-renamed $SHARE_PATH)" 201
check "the group member still reads the file"                "$(dav_get $B "$SHARE_PATH/hello.txt")" hello

transfer=$(occ files:transfer-ownership --path="${SHARE_PATH#/}" $A $C 2>&1)
check "ownership transfer reports no share errors"           "$(echo "$transfer" | grep -ciE 'error|could not|failed')" 0
SHARER=$C
check "the share moved to the new owner"                     "$(group_share_id $BG)" "$existing_id"
check "the group member still reads the file"                "$(dav_get $B "$SHARE_PATH/hello.txt")" hello

# --- showing the group again -----------------------------------------------
as_user $ADM
check "admin shows the big group again"                      "$(set_hidden_groups '[]')" '{"groups":[]} 200'
check "big group back in share suggestions"                  "$(has "$(group_matches hgtestbi)" $BG)" yes
check "the existing share can get more permissions again"    "$(change_share "$existing_id" 31 | status)" 200
delete_all_shares
delete_transferred_folders
SHARER=$A
delete_all_shares
dav $A DELETE /hgtest-other >/dev/null
dav $A DELETE /hgtest-parent2 >/dev/null

# --- a list stored with the wrong type -------------------------------------
if [ "$MODE" = docker ]; then
	# Forcing another type through occ changes the stored type, even though occ reports an error
	occ config:app:set hidden_groups groups --value "[\"$BG\"]" --type array >/dev/null
	occ config:app:set hidden_groups groups --value $BG --type string -n >/dev/null 2>&1
	# The web server caches the app config, so restart it to make it read the stored value
	docker restart "$CONTAINER" >/dev/null
	for _ in $(seq 1 60); do curl -s "$BASE/status.php" | grep -q '"installed":true' && break; sleep 1; done
	as_user $ADM
	check "a wrongly stored list does not break the share dialog" "$(has "$(exact_group_matches hgtest)" $G)" yes
	check "a wrongly stored list does not break the admin page"  "$(script_status hidden_groups-main)" 200
	check "saving the hidden groups repairs it"                  "$(set_hidden_groups '[]')" '{"groups":[]} 200'
else
	echo "SKIP  a list stored with the wrong type (needs a web server restart, only in docker mode)"
fi

# --- not logged in -------------------------------------------------------
check "anonymous requests are rejected" \
	"$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -d '{"groups":[]}' "$BASE/index.php/apps/hidden_groups/settings/groups")" 401

if [ "${E2E_CLEANUP:-0}" = 1 ]; then
	for u in $A $B $C; do occ user:delete $u >/dev/null; done
	occ group:delete $G >/dev/null
	occ group:delete $BG >/dev/null
fi

echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]
