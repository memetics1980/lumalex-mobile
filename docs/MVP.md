# MVP definition

## Product boundary

The first usable release is a private, offline reader for dictionaries a user
already owns. It supports one `.mdx` file and optional, adjacent `.mdd`
volumes. It does not upload, bundle, or redistribute dictionary content. On
Android keeps a validated app-private MDX performance copy so the reader has
predictable random access across different Storage Access Framework providers.
MDD media volumes remain lazy at their original locations.

## Acceptance criteria

1. The user chooses a dictionary folder and grants the app persistent read
   access to it.
2. The app finds adjacent, same-name MDD volumes when they exist.
3. An exact headword lookup returns every matching record, including duplicate
   headwords.
4. HTML, CSS and dictionary-authored JavaScript run in an isolated local web
   origin so normal publisher interactions work without dictionary-specific
   DOM patches.
5. Images, stylesheets, scripts, fonts and audio resolve through a
   loopback-only, tokenized content route. Resources come from paired MDD
   volumes or confined sidecars. The CSP and native navigation layer block
   external origins, frames, forms, objects, file access and unknown schemes.
6. Opening a dictionary must not decode every definition or extract all MDD
   resources; individual attachments have a caller-provided byte limit.

## Explicit non-goals

- Full-text and fuzzy search
- Online dictionaries, accounts, sync, and telemetry
- Global system-wide selection lookup
- OCR, PDF, EPUB, Anki integration, or dictionary editing
- Importing formats other than MDX/MDD

## Platform responsibilities

| Layer | Responsibility |
| --- | --- |
| Rust core | Open untrusted MDX/MDD files, lookup, bounded resource reads, cache policy |
| Generated bridge | Typed asynchronous calls between Rust and Dart |
| Flutter | Search, dictionary library, history, bookmarks, adaptive UI |
| Native adapters | File grant persistence and sandboxed HTML resource interception |

## Stable bridge contract

The generated bridge should expose a deliberately small surface:

```text
import_dictionary(mdx_path, optional_mdd_path) -> DictionaryMetadata
lookup(dictionary_ids, query) -> List<Article>
read_resource(dictionary_id, normalized_resource_path, byte_limit) -> Resource
close_dictionary(dictionary_id)
```

`Article.html` stays HTML until it reaches the renderer. The bridge must not
rewrite HTML or materialize unrestricted MDD data.

## Implementation order

1. Completed: prove MDX exact lookup in `dictionary-core` with authorized test
   samples and expose it through the generated Flutter/Rust bridge.
2. Completed on macOS: let the user select a dictionary folder, then return
   exact lookup results as non-executable plain-text previews.
3. Completed: discover same-name and numbered MDD sidecars, then expose lazy,
   per-resource reads with caller-provided byte limits through the bridge.
4. Completed: render each article as a local web application under a
   loopback-only, tokenized origin. All local assets go through the bounded
   bridge API; external origins and privileged browser capabilities remain
   blocked.
5. Completed: persist the dictionary library's local metadata (title, original
   MDX path, and import time); Android additionally retains a private MDX
   performance copy while leaving MDD media at the source.
6. Completed on macOS: retain a read-only security-scoped bookmark when the
   user imports a dictionary folder, restore it only when reopening that
   library entry, and revoke it when the entry is removed.
7. Completed for Android: import a user-selected directory with the Storage
   Access Framework, retain its read grant, recursively find MDX files and
   same-name/numbered MDD sidecars, copy MDX into private random-access storage,
   and supply lazy MDD resources via read-only process descriptors. Completed
   for iOS: select a dictionary folder in open-in-place mode, retain its scoped
   access for the process, and restore the saved bookmark after relaunch.
   Next: validate the resource interceptor, restored grants, and local audio
   playback on physical Android, iOS, macOS, and Windows devices.
8. Completed: offer at most eight offline normalized-prefix headword
   completions without decoding article definitions.
9. Completed on macOS: resolve external dictionary CSS/font resources through
   the constrained loader, prefer approved publisher sidecars over stale
   same-named MDD copies, and play local MDD pronunciations from temporary app
   cache files.
10. Replaced: dictionary scripts now run by default inside the isolated local
    origin; no user-facing compatibility switch or publisher-specific DOM
    handler is required.
11. Completed: history, bookmarks, per-dictionary zoom, dictionary ordering and
    multi-dictionary lookup. Optional full-text indexing remains later work.
