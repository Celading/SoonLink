# Web Console

The SoonLink Web console mainly serves three kinds of work.

## 1. File Browsing

- browse directories and files
- inspect file metadata
- preview text-oriented content lightly

## 2. Transfer Operations

- upload files
- create directory tasks
- watch task progress and states
- download existing file content
- use the relay station for staged files and temporary text

### Relay Text Records

- Temporary text pasted in the browser is stored as a UTF-8 `.txt` record inside the relay cache, which fits notes, meeting scraps, or copied logs.
- Remote deletion only removes the relay record and its temporary cache. It does not directly delete the real file on a device.
- After selecting a `.txt` record, the preview panel on the right can read cached content inline.
- When the text crosses the preview threshold or the sampled payload is too large, the console switches to download guidance instead of forcing an oversized inline render.
- Text records can also be restored back into the current device and directory so temporary content can be turned into a normal file when needed.

## 3. Runtime Observation

- inspect the device list
- read the current session / capability context
- perform baseline settings and health checks

## Who It Fits

- users who want to operate SoonLink directly from the browser
- developers who validate flows in the Web UI before moving into CLI / MCP automation
- maintainers who need a quick visual check that a node is healthy
