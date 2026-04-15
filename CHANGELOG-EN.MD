# CHANGELOG

Main change log for SoonLink.

Marker guide:

- `+Feature`: new capability or visible experience upgrade
- `=Fix`: behavior correction, stability improvement, or compatibility closeout
- `=Docs`: README / CHANGELOG / explanatory document sync
- `=Chore`: build, release, repository boundary, CI, and other engineering governance updates

Notes:

- `0.1.x` to `0.4.x` carry forward summarized product milestones from before the standalone repository, so the visible version chain stays continuous.
- Starting from `0.5.x`, SoonLink entered repository governance, with versioning, release notes, and collaboration traces maintained inside the repository.

---

## [Unreleased]

---

## [0.5.27] - 2026-04-06

- `=Fix` `release-artifacts` now skips only the platforms missing SDK URLs instead of failing the entire release workflow, while still creating the GitHub Release
- `=Fix` `docker-publish` now warns and skips when Docker Hub credentials are absent instead of turning the whole tag pipeline red
- `=Fix` `homebrew-tap` now warns and skips when the tap repo, token, or Darwin assets are missing, preventing noisy post-release failures
- `=Chore` Linux release bundles now fall back to an accessible beta.25 SDK URL so the minimum artifact lane can run without extra repository variables
- `=Chore` Unified GitHub Release, Docker, and Homebrew publish flows around plain dotted tags such as `0.8.27` and `0.0.5.17`
- `=Fix` Added tag-versus-`cjpm.toml` version validation to release workflows so release metadata and asset filenames cannot drift apart
- `=Fix` Restored stable repository automation by switching Homebrew CI to a temporary tap install and correcting formula wrapper rendering
- `=Docs` Synced README, CHANGELOG, troubleshooting notes, GitHub Actions guidance, runtime version fallback, and related tests to `0.5.27`

## [0.5.22] - 2026-04-06

- `+Feature` Promoted manual node endpoint modeling from plain `ip + port` records to `scheme + host + port + basePath` across Web, CLI, MCP, and automation surfaces
- `+Feature` SoonLink Node connectors now support `https` origins and reverse-proxy subpaths, allowing node-to-node access behind base-path deployments
- `=Fix` Invalid endpoint schemes are now rejected for `soonlink-http` even when the connector is inferred from the address instead of being filled explicitly
- `=Docs` Synced README, CHANGELOG, runtime version fallback, troubleshooting notes, and the release draft to `0.5.22`

## [0.5.21] - 2026-04-06

- `+Feature` Tightened the default runtime into a “UDP discovery plus manual remember” flow, while keeping mDNS, peer transfer, relay, whitelist, favorites, and advanced security out of the default surface
- `+Feature` Switched the Web console default runtime / capability context back to `SoonLink`, keeping the landing badges and capability gates aligned with the real capability set
- `=Fix` Unified placeholder auth / crypto providers to the stable `placeholder` identifier so preview-only labels no longer leak into the default runtime
- `=Chore` Added GitHub Release artifact automation, cross-platform packaging scripts, and `linux/amd64 + linux/arm64` as the default Docker publish platforms
- `=Docs` Synced version references, GitHub Actions guidance, troubleshooting notes, and the initial release draft to `0.5.21`

## [0.5.17] - 2026-04-04

- `+Feature` Turned `manual/` into the formal handbook with quick start, API, docs, skills, and troubleshooting entrypoints
- `=Docs` Rebuilt README / README-EN into a product-style landing page centered on the repository baseline, CLI / MCP, and practical entrypoints
- `=Docs` Tightened handbook navigation and release notes so repository docs no longer mix in internal collaboration guidance
- `=Chore` Unified package metadata, runtime fallback, and related tests on version `0.5.17`

## [0.5.12] - 2026-04-04

- `+Feature` Device trust states entered the mainline: `unknown / trusted / blocked`
- `+Feature` Added PIN pairing session generation and confirmation, unified across Web / CLI / MCP
- `=Fix` High-risk Web actions are now consistently gated by device trust state
- `=Fix` Directory transfer semantics were tightened to preserve the target tree and overwrite only same-path files
- `=Docs` Unified the visible name as `SoonLink`, while also documenting the spoken / technical identifier `soonlnk`
- `=Docs` Synchronized the version set with `Ignite 0500`

## [0.5.11] - 2026-03-26

- `+Feature` Established the standalone repository baseline: `README`, `LICENSE`, `CHANGELOG`, `config/`, `web/`, scripts, and CI all entered the repo together
- `+Feature` Promoted CLI and `stdio` MCP entrypoints into the mainline, covering version, status, device, file, and task queries
- `+Feature` Landed Docker Compose and Homebrew packaging flows for repository distribution validation
- `=Chore` Added a repository-boundary check script to prevent internal workspace material, local dependency mirrors, and runtime state from entering version control
- `=Docs` Synced local build, repository boundary, and packaging guidance into repository documentation

## [0.5.1] - 2026-03-28

- `+Feature` Switched the Web console to real API-driven flows and removed runtime mock-data fallback
- `+Feature` Promoted directory tasks into the mainline, including directory-tree planning, aggregated progress, and directory transfer across homogeneous SoonLink nodes
- `+Feature` Unified the design system, SVG icon system, and mobile interaction closeout
- `=Fix` Closed out the old Web upload bug that nested an extra folder around uploaded files

## [0.4.12] - archive milestone

- `+Feature` Chunk upload, Range download, and task-tracking flows were completed, significantly improving transfer stability
- `+Feature` Relay cache, favorites, whitelist, and other enhanced capabilities entered the shared evolution path, while reserving future capability-gating hooks
- `+Feature` The `WebStatic` module was refactored and the visual language between the landing page and the management page was unified
- `+Feature` Session context responses started to output runtime / capability information in a unified format
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
> Feature-complete milestone for the Golang experiment line

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
