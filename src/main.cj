package soonlnk

import soonlnk.commons.*
import soonlnk.product.*
import std.env.getCommandLine

main(): Int64 {
    runProductCli(getCommandLine())
}
