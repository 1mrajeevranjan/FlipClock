import AppKit
import CoreText

/// One selectable clock-digit font. `.system` is the built-in default —
/// `DigitFaceRenderer` falls back to `NSFont.systemFont` when
/// `postscriptName` is nil. Every other entry is a real font file bundled
/// as an app resource (see `project.yml`'s `Fonts` source entry), which
/// only becomes resolvable by `NSFont(name:size:)` once `registerAll()`
/// has run — plain bundling isn't enough, AppKit has no idea these fonts
/// exist until they're explicitly registered with the process.
struct WidgetFont: Identifiable, Hashable {
    let id: String
    let label: String
    /// Bundle resource filename, or `nil` for `.system` (nothing to
    /// register). Xcode's resource copy phase flattens the source `Fonts/`
    /// folder's subdirectories into one `Resources/` directory, so this is
    /// always a bare filename — never a subfolder-qualified path — even
    /// for fonts that live in a subfolder under `Fonts/` on disk.
    let fileName: String?
    /// The PostScript name `NSFont(name:size:)` resolves against, or `nil`
    /// to fall back to the plain system font.
    let postscriptName: String?

    static let system = WidgetFont(id: "system", label: "System", fileName: nil, postscriptName: nil)

    /// One entry per file in `Fonts/`, `postscriptName` read directly from
    /// each font via `CTFontManagerCreateFontDescriptorsFromURL` (not
    /// guessed from the filename — several files' internal PostScript
    /// names don't match their filename at all, e.g. `rroadrunner.ttf`'s
    /// actual PostScript name is just `"New"`).
    static let bundled: [WidgetFont] = [
        WidgetFont(id: "BingBamBoum", label: "Bing Bam Boum", fileName: "Bing Bam Boum.ttf", postscriptName: "BingBamBoum"),
        WidgetFont(id: "DestroyAllHumans!", label: "Destroy All Humans!", fileName: "Destroy All Humans!.otf", postscriptName: "DestroyAllHumans!"),
        WidgetFont(id: "Dynamix", label: "Dynamix", fileName: "Dynamix.ttf", postscriptName: "Dynamix"),
        WidgetFont(id: "GFS-Custom-Bubble1", label: "Bubble 1", fileName: "GFSCUS1D.ttf", postscriptName: "GFS-Custom-Bubble1"),
        WidgetFont(id: "RockFont", label: "Rock Font", fileName: "RockFont.ttf", postscriptName: "RockFont"),
        WidgetFont(id: "TennesseeCollege", label: "Tennessee College", fileName: "Tennessee College.ttf", postscriptName: "TennesseeCollege"),
        WidgetFont(id: "AngryBirds-Regular", label: "Angry Birds", fileName: "angrybirds-regular.ttf", postscriptName: "AngryBirds-Regular"),
        WidgetFont(id: "BringMeAHelicopter!", label: "Bring Me A Helicopter!", fileName: "Bring Me A Helicopter!.otf", postscriptName: "BringMeAHelicopter!"),
        WidgetFont(id: "SportfieldVarsityGrunge", label: "Sportfield Varsity — Grunge", fileName: "Sportfield Varsity-Grunge.otf", postscriptName: "SportfieldVarsityGrunge"),
        WidgetFont(id: "SportfieldVarsityItalic", label: "Sportfield Varsity — Italic", fileName: "Sportfield Varsity-Italic.otf", postscriptName: "SportfieldVarsityItalic"),
        WidgetFont(id: "SportfieldVarsityOutline1", label: "Sportfield Varsity — Outline 1", fileName: "Sportfield Varsity-Outline1.otf", postscriptName: "SportfieldVarsityOutline1"),
        WidgetFont(id: "SportfieldVarsityOutline2", label: "Sportfield Varsity — Outline 2", fileName: "Sportfield Varsity-Outline2.otf", postscriptName: "SportfieldVarsityOutline2"),
        WidgetFont(id: "SportfieldVarsityOutline3", label: "Sportfield Varsity — Outline 3", fileName: "Sportfield Varsity-Outline3.otf", postscriptName: "SportfieldVarsityOutline3"),
        WidgetFont(id: "SportfieldVarsityScrible", label: "Sportfield Varsity — Scribble", fileName: "Sportfield Varsity-Scrible.otf", postscriptName: "SportfieldVarsityScrible"),
        WidgetFont(id: "SportfieldVarsityShadow", label: "Sportfield Varsity — Shadow", fileName: "Sportfield Varsity-Shadow.otf", postscriptName: "SportfieldVarsityShadow"),
        WidgetFont(id: "SportfieldVarsityRegular", label: "Sportfield Varsity", fileName: "Sportfield Varsity.otf", postscriptName: "SportfieldVarsityRegular"),
        WidgetFont(id: "VlumpBlack", label: "Vlump Black", fileName: "Vlump Black.ttf", postscriptName: "VlumpBlack"),
        WidgetFont(id: "Vlump", label: "Vlump", fileName: "Vlump.ttf", postscriptName: "Vlump"),
        WidgetFont(id: "WhiteSquareRedYesBlackEight", label: "White Square Red Yes Black Eight", fileName: "WhiteSquareRedYesBlackEight-Regular.ttf", postscriptName: "WhiteSquareRedYesBlackEight"),
        WidgetFont(id: "WhiteSquareRedYesBlackEightPingpong-Pingpong", label: "White Square Red Yes Black Eight — Pingpong", fileName: "WhiteSquareRedYesBlackEightPingpong-Pingpong.ttf", postscriptName: "WhiteSquareRedYesBlackEightPingpong-Pingpong"),
        WidgetFont(id: "WhiteSquareRedYesBlackEightWarsaw-Warsaw", label: "White Square Red Yes Black Eight — Warsaw", fileName: "WhiteSquareRedYesBlackEightWarsaw-Warsaw.ttf", postscriptName: "WhiteSquareRedYesBlackEightWarsaw-Warsaw"),
        WidgetFont(id: "WhiteSquareRedYesBlackEightZero-Zero", label: "White Square Red Yes Black Eight — Zero", fileName: "WhiteSquareRedYesBlackEightZero-Zero.ttf", postscriptName: "WhiteSquareRedYesBlackEightZero-Zero"),
        WidgetFont(id: "YearBookMess", label: "Year Book Mess", fileName: "YrBkMess.TTF", postscriptName: "YearBookMess")
    ]

    static let all: [WidgetFont] = [.system] + bundled

    static func byID(_ id: String) -> WidgetFont {
        all.first { $0.id == id } ?? .system
    }

    /// Registers every bundled font file with the current process so
    /// `NSFont(name:size:)` can resolve their PostScript names — without
    /// this, none of the fonts in `bundled` exist as far as AppKit/CoreText
    /// are concerned, even though the files ship inside the app bundle.
    /// `.process` scope (not `.persistent`) keeps the registration local to
    /// this app rather than writing into the user's system Font Book.
    /// Called once at launch (see `AppDelegate`).
    static func registerAll() {
        for font in bundled {
            guard let fileName = font.fileName,
                  let fileURL = Bundle.main.url(forResource: fileName, withExtension: nil) else { continue }
            CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, nil)
        }
    }
}
