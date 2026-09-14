# Sealed adversarial holdout

Sealed blueprint/rendering files live outside the ordinary development data
path and include `sealed` in the rendering filename/path. The fixing agent must
not read, export, cluster, or inspect them. A benchmark custodian runs only:

```sh
python3 Tools/SpeechLab/speechlab.py sealed-evaluate \
  --blueprints /controlled/speechlab/sealed-blueprints.jsonl \
  --renderings /controlled/speechlab/sealed-renderings.jsonl \
  --aggregate-output output/speechlab/sealed-aggregate.json
```

The command evaluates into a temporary private SQLite database and releases
only `cases`, `passed`, `failed`, run identity, and completion status. The
database is destroyed with the temporary directory; no input text, case ID,
failure detail, signature, or representative leaves the boundary.

The protected cohort uses the normal blueprint/rendering contracts plus
`schema/sealed-holdout-manifest.schema.json`. Its manifest records dataset
identity/hash, count, contract versions, custodian, and the narrow disclosure
allowlist without revealing any case content.

Operational controls still matter: filesystem permissions must deny the fixing
agent direct access; CI secrets and artifact ACLs should give the custodian
exclusive access; logs must capture only aggregate stdout; sealed records must
never be passed to `failure-pack`, `export-ai`, or a development database. Hash
the sealed dataset and record the hash in protected benchmark metadata.

If an individual holdout example is disclosed, retire it from the holdout and
move it to an adversarial development set before using it to guide a fix.
