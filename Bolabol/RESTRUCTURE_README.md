# Historical Restructure Note

The one-time Bolabol rename and directory flattening was completed before the
release-hygiene campaign. The former `restructure.sh` script was destructive
and has been removed.

Do not run or recreate that script. The repository is already arranged with
`Package.swift`, `Sources/`, and `Tests/` at its root.

For historical context and rename evidence, see [`RENAME_REPORT.md`](RENAME_REPORT.md).
