# supabase/tests/superseded/

SQL test files for a migration whose own tested function/table was later
dropped or replaced by a subsequent migration in the same feature —
kept as historical documentation of what the earlier design actually
did and verified, per this repository's "do not rewrite old migrations"
convention extended to their test coverage (see each file's own header
for the specific migration that superseded it).

**Not part of the active suite.** Deliberately named `*.superseded.sql`,
not `*.test.sql`, so `docs/DEPLOYMENT.md` §8's documented test-run
command — which iterates `supabase/tests/*.test.sql` and expects every
file it runs to pass — never picks these up. Running one of these files
directly against the CURRENT migration chain is expected to fail (the
function/table it tests no longer exists in that shape); that is not a
regression.
