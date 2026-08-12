import Foundation

extension ConvertCounterexampleEngine {

    /// Said in the emitted file because the file's location does not say it.
    ///
    /// `Tests/Generated/` is not a SwiftPM target — a target is `Tests/<Name>Tests/` — so a stub
    /// written here never compiles. That is how three syntax errors in one generated file survived
    /// a green 159-test run on the subject repo (#249): nothing was reading it, including the
    /// compiler. A file that looks like a landed regression test and is inert should say so on its
    /// first screen.
    static let inertFileNotice = """
        //
        // NOT COMPILED WHERE IT SITS. `Tests/Generated/` is not a SwiftPM target — a target is
        // `Tests/<Name>Tests/` — so this file is inert until you move it into one and add the
        // import your subject needs. It is a draft to review and adopt, not a landed regression
        // test.
        """
}
