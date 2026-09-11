# Native metadata regression inputs

These retain the exact `actions`, `entities`, and `queries` sections from app-level
`Metadata.appintents/extract.actionsdata` in the Package-App-Intents-diagnostics artifact.
Other metadata sections are omitted. Values within these three sections are not rewritten.

- `collision`: run [34557984363](https://github.com/y-aplus/JibunKit/actions/runs/34557984363), source `11330b51519c8c6983274aadd5329ae4d4a7ef3c`.
  Standalone A/B each contain `Entry`/`EntryQuery`; Combined silently retains one of each.
- `namespaced`: run [34558958859](https://github.com/y-aplus/JibunKit/actions/runs/34558958859), source `635680cc3e3a0afd73efa8f6479ce3b4d4bca06f`.
  Standard explicit `persistentIdentifier` preserves both entities and queries.

These inputs test the checker against observed native output. They are not replacement
metadata for installation, nor proof of OS Shortcuts UI or Siri dispatch.
