# Release and backup workflow

The user requires a GitHub checkpoint before and after every requested change.

1. Before editing, inspect Git status, fetch origin, and commit any pending authorized project changes. Push main and create/push an annotated `v<version>-step-<NNN>-before-<short-description>` tag pointing to that checkpoint. Do not proceed with edits if this backup fails; explain the blocker.
2. Use `VERSION.json` as the current release number and step. Increment the patch for fixes/maintenance, minor for features, and major for incompatible changes. Increment the step for each completed task.
3. After validation, update VERSION.json and CHANGELOG.md. Commit using `v<version> | Step <NNN> | <clear description>`, then create/push an annotated `v<version>-step-<NNN>-after-<short-description>` tag and push main. Report any push failure honestly.
4. Keep earlier tags and commits. Never rewrite or force-push their history. Explain rollback by version and description, rather than by hash alone.
5. Update the same active vendor build folder in place: `dist/moon-v1.1.1-step-002-organized-releases/POSAdmin`. Do not create another build folder or rename this folder for routine updates; create a second copy only when necessary. Continue recording each new version and step in Git tags, commits and VERSION.json. Override the builder's output location when needed. Preserve runtime files, the build kit, and its customer exports before any PyInstaller collection that might replace a directory; never treat customer exports as obsolete builds. Keep the active executable link usable after updates.
6. Never commit customer data, databases, private signing keys, activation material, personal audit reports, dist, release-build or local-backups. GitHub checkpoints preserve source code, not these local files. Never suggest that source backups include customer data or installers.
