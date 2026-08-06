// Makes Foundation available to every file in this test target.
//
// Why it lives in its own file: this machine has Command Line Tools only, and
// CLT ships _Testing_Foundation.framework *without* its .swiftmodule. Any single
// file that imports both `Foundation` and `Testing` therefore fails to build with
// "no such module '_Testing_Foundation'" when the compiler tries to load the
// cross-import overlay — that holds for plain, scoped and @_exported imports
// alike. This file imports Foundation without importing Testing, so no overlay
// is looked up, and the re-export gives the test files the Foundation types
// (URL, Data, FileManager, UUID) they need.
@_exported import Foundation
