package soonlnk.tests

import soonlnk.commons.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class FilePreview_test {
    @TestCase
    public func resolvesCodePreviewForCangjieSources(): Unit {
        @Assert(resolvePreviewKind("/src/master/server.cj", "", false), "code")
        @Assert(resolvePreviewLanguage("/src/master/server.cj", ""), "cangjie")
        @Assert(resolvePreviewMimeType("", "/src/master/server.cj", false), "text/plain; charset=utf-8")
    }

    @TestCase
    public func resolvesInlineMediaPreviewKinds(): Unit {
        @Assert(resolvePreviewKind("/Pictures/demo.png", "", false), "image")
        @Assert(resolvePreviewMimeType("", "/Pictures/demo.png", false), "image/png")
        @Assert(resolvePreviewMimeType("", "/Pictures/live.heic", false), "image/heic")
        @Assert(resolvePreviewKind("/Movies/clip.mp4", "", false), "video")
        @Assert(resolvePreviewKind("/Music/theme.mp3", "", false), "audio")
        @Assert(resolvePreviewKind("/Docs/file.pdf", "", false), "pdf")
    }

    @TestCase
    public func resolvesDocumentAndArchiveMimeTypes(): Unit {
        @Assert(resolvePreviewMimeType("", "/Docs/spec.yaml", false), "application/yaml")
        @Assert(resolvePreviewMimeType("", "/Docs/table.xlsx", false), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        @Assert(resolvePreviewMimeType("", "/Downloads/backup.tar.gz", false), "application/gzip")
    }

    @TestCase
    public func keepsDirectoryAndUnsupportedEntriesOutOfPreview(): Unit {
        @Assert(resolvePreviewKind("/Downloads/archive.zip", "", false), "unsupported")
        @Assert(resolvePreviewKind("/Downloads/folder", "", true), "directory")
        @Assert(!isTextPreviewKind("unsupported"))
        @Assert(isTextPreviewKind("text"))
        @Assert(isTextPreviewKind("code"))
    }
}
