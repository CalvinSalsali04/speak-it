# Generation manifests

`captures.sha256` holds one hash per capture of each sealed set, and
`../generations.tsv` holds the generation each set is currently on.
`../everyday/generation-check.py` compares them to the sets on disk.

The hashes are of the capture text alone. A hash does not reveal a capture, so
committing this file does not unseal anything, and a hash is what lets the
check say *how many* captures changed rather than only that something did.

Do not regenerate these by hand or by re-running the recorder to make a red
check go green. Editing a capture in a set that has already been scored opens
a new generation, and the point of the check is to make that a decision
somebody takes rather than a diff nobody notices.
