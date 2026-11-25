# Release and backup workflow

The user requires a GitHub checkpoint before and after every requested change.

1. Before editing, inspect Git status, fetch origin, and commit any pending authorized project changes. Push main and create/push an annotated `v<version>-step-<NNN>-before-<short-description>` tag pointing to that checkpoint. Do not proceed with edits if this backup fails; explain the blocker.
2. Use `VERSION.json` as the current release number and step. Increment the patch for fixes/maintenance, minor for features, and major for incompatible changes. Increment the step for each completed task.
3. After validation, update VERSION.json and CHANGELOG.md. Commit using `v<version> | Step <NNN> | <clear description>`, then create/push an annotated `v<version>-step-<NNN>-after-<short-description>` tag and push main. Report any push failure honestly.
4. Keep earlier tags and commits. Never rewrite or force-push their history. Explain rollback by version and description, rather than by hash alone.
5. Keep only the latest vendor build in dist, named `moon-v<version>-step-<NNN>-<description>`. Preserve required runtime files and the build kit together. Remove older builds only after checking the latest one and preserving unique customer records locally.
6. Never commit customer data, databases, private signing keys, activation material, personal audit reports, dist, release-build or local-backups. GitHub checkpoints preserve source code, not these local files. Never suggest that source backups include customer data or installers.
