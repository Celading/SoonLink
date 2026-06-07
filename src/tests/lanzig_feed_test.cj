package soonlnk.tests

import soonlnk.commons.*
import soonlnk.master.*
import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class LanzigFeed_test {
    @TestCase
    public func buildsReadOnlyFeedFromMarkdownFilesOnly(): Unit {
        let entries = ArrayList<FileEntry>()

        let note = FileEntry()
        note.name = "welcome.md"
        note.path = "/lanzig-feed/welcome.md"
        note.size = 42
        note.modified = 1700000000
        entries.add(note)

        let other = FileEntry()
        other.name = "draft.txt"
        other.path = "/lanzig-feed/draft.txt"
        other.size = 11
        entries.add(other)

        let dir = FileEntry()
        dir.name = "subdir"
        dir.path = "/lanzig-feed/subdir"
        dir.isDir = true
        entries.add(dir)

        let feed = buildLanzigFeedPayloadFromEntries("http://localhost:8081", entries)
        let raw = feed.toString()

        @Assert(raw.contains("\"version\":\"lanzig.feed.v0\""))
        @Assert(raw.contains("\"readOnly\":true"))
        @Assert(raw.contains("\"passiveSync\":false"))
        @Assert(raw.contains("\"feedUrl\":\"http://localhost:8081/api/lanzig/feed.json\""))
        @Assert(raw.contains("\"markdownUrl\":\"http://localhost:8081/api/lanzig/md/welcome.md\""))
        @Assert(raw.contains("\"path\":\"./md/welcome.md\""))
        @Assert(raw.contains("\"title\":\"welcome\""))
        @Assert(!raw.contains("draft.txt"))
        @Assert(!raw.contains("subdir"))
    }

    @TestCase
    public func preservesSafeNoteIdForMarkdownEndpoint(): Unit {
        match (resolveLanzigMarkdownPath("hello")) {
            case Some(path) => @Assert(path, "/lanzig-feed/hello.md")
            case None => @Assert(false)
        }

        match (resolveLanzigMarkdownPath("hello.md")) {
            case Some(path) => @Assert(path, "/lanzig-feed/hello.md")
            case None => @Assert(false)
        }

        match (resolveLanzigMarkdownPath("../escape")) {
            case Some(_path) => @Assert(false)
            case None => @Assert(true)
        }
    }

    @TestCase
    public func buildsStatusPayloadForSettingsSurface(): Unit {
        let entries = ArrayList<FileEntry>()

        let note = FileEntry()
        note.name = "alpha.md"
        entries.add(note)

        let hidden = FileEntry()
        hidden.name = ".hidden.md"
        entries.add(hidden)

        let doc = FileEntry()
        doc.name = "beta.markdown"
        entries.add(doc)

        let status = buildLanzigFeedStatusPayloadFromEntries("http://localhost:8081", entries)
        let raw = status.toString()

        @Assert(raw.contains("\"success\":true"))
        @Assert(raw.contains("\"protocol\":\"lanzig.feed.v0\""))
        @Assert(raw.contains("\"feedUrl\":\"http://localhost:8081/api/lanzig/feed.json\""))
        @Assert(raw.contains("\"markdownRoute\":\"http://localhost:8081/api/lanzig/md/:noteId\""))
        @Assert(raw.contains("\"sourcePath\":\"/lanzig-feed\""))
        @Assert(raw.contains("\"itemCount\":2"))
        @Assert(raw.contains("\"readOnly\":true"))
        @Assert(raw.contains("\"passiveSync\":false"))
    }
}
