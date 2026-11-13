import Foundation

public enum PageTemplate {
    public static func columnTitles(in language: PageLanguage) -> [String] {
        ColumnKind.allCases.map { $0.title(in: language) }
    }

    public static func storage(language: PageLanguage) -> String {
        let legend = BugStatus.allCases.map { "\($0.macro(in: language)) \($0.legend(in: language))" }
        let introduction = [
            "<p>\(language.vocabulary.templateOpening)</p>",
            "<p>\(legend.joined(separator: " &nbsp; "))</p>",
            "<p>\(language.vocabulary.templateClosing)</p>",
        ]
        let information = "<ac:structured-macro ac:name=\"info\" ac:schema-version=\"1\"><ac:rich-text-body>\(introduction.joined())</ac:rich-text-body></ac:structured-macro>"
        let columns = ColumnKind.allCases.map { "<col style=\"width: \($0.widthPercentage).0%;\" />" }
        let headerCells = ColumnKind.allCases.map { "<th>\($0.title(in: language))</th>" }
        let table = "<table class=\"relative-table wrapped\" style=\"width: 100.0%;\"><colgroup>\(columns.joined())</colgroup><tbody><tr>\(headerCells.joined())</tr></tbody></table>"
        return information + table
    }
}
