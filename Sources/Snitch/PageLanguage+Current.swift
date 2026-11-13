import Foundation
import SnitchCore

extension PageLanguage {
    static var current: PageLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("it") == true ? .italian : .english
    }
}
