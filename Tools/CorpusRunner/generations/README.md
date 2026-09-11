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

That last sentence is a claim about what cannot happen quietly, so here is what
makes it hold rather than an assurance that it does. The check runs in the
`language-tools` job of `.github/workflows/ci.yml`, and all five files it reads
— `../everyday/everyday.tsv`, `../heldout/heldout.tsv`,
`../adversarial/adversarial.tsv`, `../generations.tsv` and `captures.sha256` —
live under `Tools/CorpusRunner/**`, which is the path filter gating that job.
So there is no edit to a scored capture that does not run it, and none that
rewrites the record to match either. Put the five paths beside the filter and
the claim is either true or visibly not.

It was not true until the step was wired in, and this paragraph landed with it.
The sentence above it sat here asserting the property for as long as the check
ran nowhere, which is the failure a bare property invites: it reads as
guaranteed, and nothing on the page tells a reader how to find out.
