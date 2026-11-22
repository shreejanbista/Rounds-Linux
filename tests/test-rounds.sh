#!/usr/bin/env bash
# Tests the `rounds` launcher and `rounds upgrade` against a pretend GitHub and a pretend Rounds,
# so nothing real is downloaded or changed. Needs Node 20+.
# Usage: tests/test-rounds.sh [path-to-rounds]   (defaults to ./bin/rounds)
set -uo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROUNDS="${1:-$here/bin/rounds}"
t="$(mktemp -d)"; pid=""
trap '[[ -n "$pid" ]] && kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
pass=0 fail=0
check() { if eval "$2"; then echo "  ok    $1"; ((pass++)); else echo "  FAIL  $1"; ((fail++)); fi; }

OLD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa NEW=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# A pretend Rounds in ~/.rounds/app: prints what it was given, exits 3 when told "fail".
mkdir -p "$t/home/app/bin"
cat > "$t/home/app/bin/rounds.mjs" <<'EOF'
console.log("RAN:" + process.argv.slice(2).join(" "));
process.exit(process.argv.includes("fail") ? 3 : 0);
EOF
echo '{"name":"rounds-app","version":"1.1.1"}' > "$t/home/app/package.json"
# ...and the npx download it came from, which names the exact commit.
mkdir -p "$t/npx/abc/node_modules"
cp -r "$t/home/app" "$t/npx/abc/node_modules/rounds-app"
echo "{\"packages\":{\"node_modules/rounds-app\":{\"resolved\":\"git+ssh://git@github.com/krispuckett/rounds.git#$OLD\"}}}" > "$t/npx/abc/package-lock.json"

# A pretend npx: records how it was called, then "installs" 1.2.0.
cat > "$t/npx.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$t/npx-called"
echo '{"name":"rounds-app","version":"1.2.0"}' > "$t/home/app/package.json"
EOF
chmod +x "$t/npx.sh"

# A pretend GitHub API.
cat > "$t/api.mjs" <<EOF
import http from "node:http";
const pkg = Buffer.from(JSON.stringify({ version: "1.2.0" })).toString("base64");
const c = (m, d) => ({ commit: { message: m, committer: { date: d } } });
const routes = {
  "/repos/krispuckett/rounds/commits/HEAD": { sha: "$NEW", commit: { committer: { date: "2026-12-01T10:00:00Z" } } },
  "/repos/krispuckett/rounds/contents/package.json?ref=$NEW": { content: pkg },
  "/repos/krispuckett/rounds/compare/$OLD...$NEW": { status: "ahead", ahead_by: 2,
    commits: [c("Add: a darker canvas at night\n\nlonger text", "2026-11-28T00:00:00Z"), c("Fix: notes reach the right session", "2026-12-01T00:00:00Z")] },
};
const s = http.createServer((q, r) => { const b = routes[q.url]; r.writeHead(b ? 200 : 404, { "content-type": "application/json" }); r.end(JSON.stringify(b || {})); });
s.listen(0, "127.0.0.1", () => console.log(s.address().port));
EOF
node "$t/api.mjs" > "$t/port" & pid=$!
for _ in $(seq 50); do [[ -s "$t/port" ]] && break; sleep 0.1; done

export ROUNDS_HOME="$t/home" ROUNDS_LINUX_API="http://127.0.0.1:$(cat "$t/port")" \
  ROUNDS_LINUX_NPX="$t/npx.sh" ROUNDS_LINUX_NPX_CACHE="$t/npx" ROUNDS_LINUX_NO_CHECK=1
r() { "$ROUNDS" "$@" </dev/null 2>&1; }
state() { node -p "JSON.parse(require('fs').readFileSync('$t/home/rounds-linux.json','utf8'))$1" 2>/dev/null; }

echo "rounds launcher: $ROUNDS"
out="$(r index --demo)"
check "passes every word through to Rounds" '[[ "$out" == *"RAN:index --demo"* ]]'
r fail >/dev/null; code=$?
check "passes Rounds' exit code back" '((code == 3))'

out="$(r upgrade --check)"
check "finds which build you have from npm's download" '[[ "$out" == *"1.1.1 (aaaaaaa)"* ]]'
check "shows the new version" '[[ "$out" == *"Rounds 1.2.0 is out"* ]]'
check "lists Kris's changes, newest first, first line only" '[[ "$out" == *"2 changes"* && "$out" != *"longer text"* && "$(grep -n "Fix: notes" <<<"$out" | cut -d: -f1)" -lt "$(grep -n "Add: a darker" <<<"$out" | cut -d: -f1)" ]]'
check "links the full code changes" '[[ "$out" == *"compare/aaaaaaa...bbbbbbb"* ]]'
check "--check installs nothing" '[[ ! -e "$t/npx-called" ]]'

out="$(r upgrade)"; code=$?
check "won't install without an answer (no terminal, no --yes)" '((code != 0)) && [[ ! -e "$t/npx-called" ]]'

out="$(r)"
check "on start, says a newer Rounds is out (one line)" '[[ "$out" == *"Rounds 1.2.0 is out: run \`rounds upgrade\`"* && "$out" == *"RAN:"* ]]'

out="$(r upgrade --yes)"
check "installs the exact new commit through Rounds' own update" '[[ "$(cat "$t/npx-called" 2>/dev/null)" == "--yes --allow-git=root github:krispuckett/rounds#$NEW update" ]]'
check "remembers the new build" '[[ "$(state .installed.sha)" == "$NEW" && "$(state .installed.version)" == 1.2.0 ]]'
out="$(r upgrade --check)"
check "then reports up to date" '[[ "$out" == *"up to date"* ]]'
out="$(r)"
check "and says nothing extra on start" '[[ "$out" == "RAN:" ]]'

export ROUNDS_LINUX_API="http://127.0.0.1:9"
out="$(r upgrade --check)"; code=$?
check "offline: upgrade says it couldn't check" '((code != 0)) && [[ "$out" == *"Couldn"*"check"* ]]'
unset ROUNDS_LINUX_NO_CHECK
start=$(date +%s%N); out="$(r)"; ms=$(( ($(date +%s%N) - start) / 1000000 ))
check "offline: the canvas still starts, without waiting (${ms}ms)" '[[ "$out" == "RAN:" ]] && ((ms < 2000))'
export ROUNDS_LINUX_NO_CHECK=1

ROUNDS_HOME="$t/empty" out="$(r)"; code=$?
check "not set up yet: says how, and stops" '((code != 0)) && [[ "$out" == *"init"* ]]'

echo "$pass passed, $fail failed"
((fail == 0))
