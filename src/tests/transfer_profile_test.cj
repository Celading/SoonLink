package soonlnk.tests

import soonlnk.commons.*
import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class TransferProfile_test {
    @TestCase
    public func resolvesFileCategoriesAcrossCommonTypes(): Unit {
        @Assert(resolveTransferFileCategory("/Pictures/live.heic", "", false), "image")
        @Assert(resolveTransferFileCategory("/Docs/spec.yaml", "", false), "document")
        @Assert(resolveTransferFileCategory("/Docs/table.xlsx", "", false), "document")
        @Assert(resolveTransferFileCategory("/Downloads/backup.tar.gz", "", false), "archive")
        @Assert(resolveTransferFileCategory("/src/main.cj", "", false), "code")
        @Assert(resolveTransferFileCategory("/relay/cache.txt", "", false), "text")
        @Assert(resolveTransferFileCategory("/relay/inbox", "", true), "directory")
    }

    @TestCase
    public func buildsProtocolCandidatesWithPreferencesAndFallbacks(): Unit {
        let explicit = ArrayList<String>()
        explicit.add("quic")
        explicit.add("http")
        explicit.add("bogus")
        explicit.add("http")

        let directoryCandidates = buildTransferProtocolCandidates("directory", 0, ArrayList<String>(), true, 0)
        let documentCandidates = buildTransferProtocolCandidates("document", 32 * 1024, ArrayList<String>(), false, 0)
        let videoCandidates = buildTransferProtocolCandidates("video", 512 * 1024 * 1024, ArrayList<String>(), false, 0)
        let preferredCandidates = buildTransferProtocolCandidates("document", 32 * 1024, explicit, false, 0)

        @Assert(directoryCandidates[0], "rsync")
        @Assert(documentCandidates[0], "http")
        @Assert(videoCandidates[0], "multi-thread-http")
        @Assert(preferredCandidates[0], "quic")
        @Assert(preferredCandidates[1], "http")
    }
}
