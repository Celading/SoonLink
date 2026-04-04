package soonlnk.tests

import soonlnk.commons.*
import soonlnk.product.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class EditionProjection_test {
    @TestCase
    public func buildProductFollowsResolvedEdition(): Unit {
        let profile = resolveProductProfile()
        let product = buildProduct(AppConfig())
        @Assert(product.name(), profile.productName)
    }
}
