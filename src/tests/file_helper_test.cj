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

    @TestCase
    public func writeUtf8TextWithoutQuestionMarks(): Unit {
        let path = testTempPath("soonlink_file_helper_utf8") + ".txt"
        let helper = FileHelper(LocalFileMgr())
        let content = "备案号\n你好，SoonLink"

        helper.writeText(path, content, "utf-8")

        let read = helper.readTextAuto(path)
        @Assert(read.ok, true)
        @Assert(read.encoding, "utf-8")
        @Assert(read.content, content)

        match (helper.readLine(path, 2)) {
            case Some(line) => @Assert(line, "你好，SoonLink")
            case None => @Assert(false)
        }

        remove(path)
    }
}
