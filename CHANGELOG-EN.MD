# CHANGELOG

Main change log for the public open-source edition of SoonLink.

Marker guide:

- `+Feature`: new capability or visible experience upgrade
- `=Fix`: behavior correction, stability improvement, or compatibility closeout
- `=Docs`: README / CHANGELOG / explanatory document sync
- `=Chore`: build, release, repository boundary, CI, and other engineering governance updates

Notes:

- `0.1.x` to `0.4.x` carry forward summarized product milestones from before the standalone public repository, so the visible version chain stays continuous.
- Starting from `0.5.x`, SoonLink entered public repository governance, with versioning, release notes, and collaboration traces maintained inside the repository.

---

## [Unreleased]

---

## [0.5.17] - 2026-04-04

- `+Feature` Turned `manual/` into the formal open-source handbook with quick start, API, docs, skills, and troubleshooting entrypoints
- `=Docs` Rebuilt README / README-EN into a product-style landing page centered on the open-source baseline, CLI / MCP, and practical entrypoints
- `=Docs` Tightened handbook navigation and release notes so public-facing docs no longer mix in internal collaboration guidance
- `=Chore` Unified package metadata, runtime fallback, and related tests on version `0.5.17`

## [0.5.12] - 2026-04-04

- `+Feature` Device trust states entered the mainline: `unknown / trusted / blocked`
- `+Feature` Added PIN pairing session generation and confirmation, unified across Web / CLI / MCP
- `=Fix` High-risk Web actions are now consistently gated by device trust state
- `=Fix` Directory transfer semantics were tightened to preserve the target tree and overwrite only same-path files
- `=Docs` Unified the public-facing name as `SoonLink`, while also documenting the spoken / technical identifier `soonlnk`
- `=Docs` Synchronized the version set with `Ignite 0500`

## [0.5.11] - 2026-03-26

- `+Feature` Established the standalone public repository baseline: `README`, `LICENSE`, `CHANGELOG`, `config/`, `web/`, public scripts, and CI all entered the repo together
- `+Feature` Promoted CLI and `stdio` MCP entrypoints into the public mainline, covering version, status, device, file, and task queries
- `+Feature` Landed Docker Compose and Homebrew packaging flows for public distribution validation
- `=Chore` Added a public-boundary check script to prevent internal workspace material, local dependency mirrors, and runtime state from entering version control
- `=Docs` Synced local build, public boundary, and packaging guidance into repository documentation

## [0.5.1] - 2026-03-28

- `+Feature` Switched the Web console to real API-driven flows and removed runtime mock-data fallback
- `+Feature` Promoted directory tasks into the mainline, including directory-tree planning, aggregated progress, and directory transfer across homogeneous SoonLink nodes
- `+Feature` Unified the design system, SVG icon system, and mobile interaction closeout
- `=Fix` Closed out the old Web upload bug that nested an extra folder around uploaded files

## [0.4.12] - archive milestone

- `+Feature` Chunk upload, Range download, and task-tracking flows were completed, significantly improving transfer stability
- `+Feature` Relay cache, favorites, whitelist, and other enhanced capabilities entered the shared evolution path, while reserving edition-gating hooks
- `+Feature` The `WebStatic` module was refactored and the visual language between the public page and the management page was unified
- `+Feature` Session context responses started to output edition / capability information in a unified format
- `=Fix` Web-side upload, download, and task-list error handling became clearer
- `+Feature` SoonLink Web console reached a complete loop: devices, files, upload, download, transfer tasks, health, and Swagger
- `+Feature` The management entry, runtime state machine, and file-browser interactions completed their first integration pass
- `=Fix` Large-directory truncation, upload validation, and localhost management robustness were improved
- `=Chore` Integrated the `Ignite 0400` baseline version

## [0.3.61] - 2026-03-10

- `+Feature` Added dark and light color modes to the `WebStatic` module
- `+Feature` Added LocalStorage-based persistence in `WebStatic` for favorite folders and theme-color memory
- `+Feature` Added favorite-folder support to the `WebStatic` module

## [0.3.20] - 2026-03-10

- `+Feature` Added seamless privilege detection, automatically entering administrator mode when running on `localhost`
- `+Feature` The file system REST API, task CRUD, device registration, and local shared-root model became basically complete
- `+Feature` Integrated the base logging system with CangjieApi2 / lisi companion capabilities
- `=Docs` Started maintaining Chinese and English README files together with synchronized change traces

## [0.3.12] - 2025-03-15
> Full feature-complete milestone for the Golang experiment line

- `+Feature` `CoreServer`, `WebServer`, `FileSystemManager`, `TransferEngine`, and related base modules formed a minimum closed loop
- `+Feature` The local device model, upload/download flows, task creation, and multi-thread transfer prototype were established
- `=Fix` Local file visibility, API responses, and baseline error handling received their first closeout pass

## [0.2.12] - 2026-03-01

- `=Chore` SoonLink executable baseline
- `=Chore` SoonLink `0200Final` milestone

## [0.2.1] - 2026-03-01

- `+Feature` SoonLink advanced from an early prototype into a continuously verifiable cross-device transfer service shape
- `+Feature` Core domain models for devices, paths, tasks, and transfer protocols started to stabilize
- `=Chore` The full capability line migrated into the `Cangjie` ecosystem, with `Ignite` as the main server-side foundation
- `=Chore` The project moved from “experimental scripts” to a sustainably evolving service-engineering structure

## Golang version - archive milestone
> Experimental skeleton line

### [0.12.22] - 2025-07-11

- `=Chore` Final closeout version of the `Golang` framework line
- `+Feature` Improved `WebStatic`
- `+Feature` Added adaptation for phones, tablets, PCs, and other device classes

### [0.1.0] - 2025-03-20

- `=Chore` Established the initial skeleton with the `Golang` version as the baseline
- `+Feature` Built the first version baseline: local file browsing, single-device transfer, basic configuration, and service startup
- `+Feature` SoonLink’s product direction formally converged on “a cross-device file transfer and management backend”
