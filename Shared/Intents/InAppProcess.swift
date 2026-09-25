#if os(iOS) && INTENTS_IN_APP_PROCESS
// Escape hatch (risk R2): building with INTENTS_IN_APP_PROCESS makes the iPhone run the widget and
// control intents in the app process instead of the widget extension. The watch has no equivalent.
import AppIntents
extension QuickLogIntent: LiveActivityIntent {}
extension UndoLastIntent: LiveActivityIntent {}
#endif
