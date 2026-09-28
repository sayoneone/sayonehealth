import SayoneCore

/// SayoneCore.Phrasebook in the current language, keyed by our outcome types.
enum SiriText {
    static func logged(_ o: LogOutcome) -> String {
        let lang = AppLanguage.current
        if !o.stored {
            return Phrasebook.storeFailed(lang)
        }
        if o.isDuplicate {
            return Phrasebook.duplicateIgnored(lang)
        }
        return Phrasebook.logged(drinkName: o.entry.drinkName,
                                 volumeML: o.entry.volumeML,
                                 summary: o.summary,
                                 savedToHealth: o.savedToHealth,
                                 healthAuthorized: o.healthAuth == .authorized,
                                 lang)
    }

    static func today(_ s: TodaySummary) -> String {
        Phrasebook.today(s, .current)
    }

    static func undone(_ r: UndoResult) -> String {
        let lang = AppLanguage.current
        switch r.outcome {
        case .deleted:
            guard let entry = r.entry else { return Phrasebook.nothingToUndo(lang) }
            return Phrasebook.undone(drinkName: entry.drinkName, volumeML: entry.volumeML, lang)
        case .queued:
            guard let entry = r.entry else { return Phrasebook.nothingToUndo(lang) }
            return Phrasebook.undoQueued(drinkName: entry.drinkName, volumeML: entry.volumeML, lang)
        case .notDeletableHere:
            return Phrasebook.notDeletableHere(lang)
        case .notFound:
            return Phrasebook.nothingToUndo(lang)
        case .failed:
            return Phrasebook.storeFailed(lang)
        }
    }

    static var healthAccessMissing: String {
        Phrasebook.healthAccessMissing(.current)
    }
}
