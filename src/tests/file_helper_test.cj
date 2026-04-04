package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class FileHelper_test {
    @TestCase
    public func detectAndReadLine(): Unit {
        let path = testTempPath("soonlink_file_helper") + ".txt"
        let helper = FileHelper(LocalFileMgr())

        helper.writeText(path, "line1\nline2\nline3", "utf-8")

        let enc = helper.detectEncoding(path)
        @Assert(enc, "utf-8")

        match (helper.readLine(path, 2)) {
            case Some(line) => @Assert(line, "line2")
            case None => @Assert(false)
        }

        remove(path)
    }
}
