package soonlnk.tests

import soonlnk.commons.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class UtilsFormat_test {
    @TestCase
    public func parsesEscapedJsonStringControlsWithoutFlatteningText(): Unit {
        let payload = "{\"content\":\"# 标题\\n\\n1. 第一行\\n- 第二行\\t\\\"quote\\\"\\\\tail\"}"
        let expected = "# 标题\n\n1. 第一行\n- 第二行\t\"quote\"\\tail"
        @Assert(parseJsonString(payload, "content") ?? "", expected)
    }

    @TestCase
    public func formatsByteSizesWithRoundedReadableUnits(): Unit {
        let gb = 1024 * 1024 * 1024
        @Assert(formatBytes(0), "0 B")
        @Assert(formatBytes(73), "73 B")
        @Assert(formatBytes(1024), "1 KB")
        @Assert(formatBytes(1536), "1.5 KB")
        @Assert(formatBytes(1048575), "1024 KB")
        @Assert(formatBytes(1048576), "1 MB")
        @Assert(formatBytes(1572864), "1.5 MB")
        @Assert(formatBytes(5 * gb + gb / 2), "5.5 GB")
        @Assert(formatBytes(10 * gb), "10 GB")
    }
}
