# App Store metadata for 2.0

The texts and answers for the App Store Connect record of SlidePilot 2.0 (issue #41), in English, German and French. They are entered in App Store Connect after review; this file is the source. The number after each field is App Store Connect's limit (characters; bytes for keywords).

Rules for the texts:
- The App Store version and its listing do not mention the free Mac download (ADR 0011, 0020).
- No other company's trademarks (e.g. Keynote, PowerPoint) in the name, subtitle or keywords.
- The in-app purchase is named, so nobody downloads the app expecting unlimited presenting for free (App Review Guideline 3.1.1, 2.3.2).

## Record-wide settings

| Field | Value |
|---|---|
| Name | SlidePilot |
| Primary category | Productivity |
| Secondary category | Education |
| Price | Free, in every storefront (ADR 0020) |
| In-app purchase | SlidePilot Pro, non-consumable, 7.99 EUR, Family Sharing on (see `docs/release.md`) |
| Age rating | Every question "None" / "No" → 4+ |
| Copyright | `2026` followed by the copyright holder named in `LICENSE` |
| Support URL | https://docs.slidepilotapp.com |
| Marketing URL | https://github.com/SlidePilot/SlidePilot-Universal |
| Privacy policy URL | https://github.com/SlidePilot/SlidePilot-Universal/blob/main/docs/privacy-policy.md ([text](privacy-policy.md)) |

## English (en-US, also used for en-GB, en-AU, en-CA)

**Subtitle** (30)
> PDF presenter for LaTeX Beamer

**Keywords** (100 bytes)
> presenter,presentation,slides,speaker notes,timer,remote,pointer,lecture,teaching,talk,conference

**Promotional text** (170)
> Present your PDF slides with notes, timer, pointer and drawing. Control the presentation from your iPhone, iPad or Mac.

**Description** (4000)
> SlidePilot is a presenter for PDF slides, made for decks from LaTeX Beamer. The audience sees your slides on the projector or external display; you see the current slide, the next slide, your notes and the time.
>
> PRESENTER VIEW
> • Current slide, next slide and notes side by side, in the layout you choose
> • Clock and stopwatch, or a countdown timer with two warnings before the time is up
> • Slide navigator with thumbnails and jump to any page
> • Black or white screen to pause the presentation
>
> NOTES
> • Write rich-text notes for every slide
> • Beamer notes on the second screen: SlidePilot shows the notes half of each page to you and the slide half to the audience, and detects the position from the PDF keywords SP-Right, SP-Left, SP-Top and SP-Bottom
> • Notes, drawings and settings are kept with each PDF and can be exported as a .slidepilot file
>
> POINTER AND DRAWING
> • Show a pointer on the audience screen: dot, circle, target, cursor or your own design
> • Draw on the current slide with your mouse, finger or Apple Pencil; keep the drawings or export them as a PDF
>
> MADE FOR LATEX
> • Reloads automatically when you recompile the PDF and stays on the same slide
> • Internal links, web links and videos embedded with Beamer work during the talk
>
> REMOTE CONTROL
> • Control a presentation on your Mac or iPad from your iPhone, or from any other device with SlidePilot
> • Devices pair once with a code shown on both screens; the connection is encrypted
>
> ON EVERY DEVICE
> • One app for Mac, iPad and iPhone, with an external display by cable or AirPlay
> • Keyboard shortcuts and presentation clickers, VoiceOver, Dynamic Type, dark mode
> • English, German and French
>
> SLIDEPILOT PRO
> SlidePilot is free to download. Everything on your own screen is unlimited: opening PDFs, the presenter view, notes, timer, pointer and drawing. Presenting to an audience screen and remote control can be tried for 3 minutes at a time. The one-time in-app purchase SlidePilot Pro unlocks them without limits on all your devices, also for your family through Family Sharing.
>
> SlidePilot is open source. No account, no tracking, no data collected.

**What's New** (4000)
> SlidePilot 2.0 is a complete rewrite for macOS, iPadOS and, for the first time, iPhone.
> • New: remote control between any two devices with SlidePilot, paired with a code and encrypted
> • New: several PDFs open at once, each with its own presenter and presentation window
> • New: notes, drawings and settings are kept with each PDF and can be exported as a .slidepilot file
> • New: countdown timer with two warnings, automatic lists in notes, Apple Pencil support
> • Native design for macOS 26 and iPadOS 26, with VoiceOver, Dynamic Type and dark mode

## German (de-DE)

**Subtitle** (30)
> PDF-Präsentation für Beamer

**Keywords** (100 bytes)
> Präsentation,Folien,Vortrag,Notizen,Referent,Timer,Fernbedienung,Zeiger,LaTeX,Vorlesung,Lehre

**Promotional text** (170)
> Präsentiere deine PDF-Folien mit Notizen, Timer, Zeiger und Zeichnen. Steuere die Präsentation von deinem iPhone, iPad oder Mac.

**Description** (4000)
> SlidePilot präsentiert PDF-Folien und ist für Präsentationen aus LaTeX Beamer gemacht. Das Publikum sieht deine Folien auf dem Projektor oder externen Bildschirm; du siehst die aktuelle Folie, die nächste Folie, deine Notizen und die Zeit.
>
> REFERENTENANSICHT
> • Aktuelle Folie, nächste Folie und Notizen nebeneinander, im Layout deiner Wahl
> • Uhr und Stoppuhr oder ein Countdown mit zwei Warnungen, bevor die Zeit abläuft
> • Folienübersicht mit Miniaturen und Sprung zu jeder Seite
> • Schwarzer oder weißer Bildschirm, um die Präsentation zu unterbrechen
>
> NOTIZEN
> • Formatierte Notizen zu jeder Folie
> • Beamer-Notizen auf dem zweiten Bildschirm: SlidePilot zeigt dir die Notizhälfte jeder Seite und dem Publikum die Folienhälfte und erkennt die Position an den PDF-Schlüsselwörtern SP-Right, SP-Left, SP-Top und SP-Bottom
> • Notizen, Zeichnungen und Einstellungen bleiben bei jedem PDF und lassen sich als .slidepilot-Datei exportieren
>
> ZEIGER UND ZEICHNEN
> • Ein Zeiger auf dem Bildschirm des Publikums: Punkt, Kreis, Zielscheibe, Mauszeiger oder dein eigenes Design
> • Zeichne auf der aktuellen Folie mit Maus, Finger oder Apple Pencil; behalte die Zeichnungen oder exportiere sie als PDF
>
> GEMACHT FÜR LATEX
> • Lädt automatisch neu, wenn du das PDF neu kompilierst, und bleibt auf derselben Folie
> • Interne Links, Weblinks und mit Beamer eingebettete Videos funktionieren im Vortrag
>
> FERNSTEUERUNG
> • Steuere eine Präsentation auf Mac oder iPad mit deinem iPhone oder einem anderen Gerät mit SlidePilot
> • Geräte koppeln sich einmal mit einem Code, der auf beiden Bildschirmen erscheint; die Verbindung ist verschlüsselt
>
> AUF JEDEM GERÄT
> • Eine App für Mac, iPad und iPhone, mit externem Bildschirm per Kabel oder AirPlay
> • Tastenkürzel und Presenter, VoiceOver, dynamische Schriftgröße, Dunkelmodus
> • Deutsch, Englisch und Französisch
>
> SLIDEPILOT PRO
> SlidePilot ist kostenlos. Alles auf deinem eigenen Bildschirm ist unbegrenzt: PDFs öffnen, Referentenansicht, Notizen, Timer, Zeiger und Zeichnen. Präsentieren auf einem Bildschirm für das Publikum und die Fernsteuerung kannst du jeweils 3 Minuten lang testen. Der einmalige In-App-Kauf SlidePilot Pro schaltet sie unbegrenzt auf allen deinen Geräten frei, über die Familienfreigabe auch für deine Familie.
>
> SlidePilot ist Open Source. Kein Konto, kein Tracking, keine Datenerfassung.

**What's New** (4000)
> SlidePilot 2.0 ist eine komplette Neuentwicklung für macOS, iPadOS und erstmals iPhone.
> • Neu: Fernsteuerung zwischen zwei beliebigen Geräten mit SlidePilot, gekoppelt mit einem Code und verschlüsselt
> • Neu: mehrere PDFs gleichzeitig, jedes mit eigenem Referenten- und Präsentationsfenster
> • Neu: Notizen, Zeichnungen und Einstellungen bleiben bei jedem PDF und lassen sich als .slidepilot-Datei exportieren
> • Neu: Countdown mit zwei Warnungen, automatische Listen in Notizen, Unterstützung für Apple Pencil
> • Natives Design für macOS 26 und iPadOS 26, mit VoiceOver, dynamischer Schriftgröße und Dunkelmodus

## French (fr-FR, also used for fr-CA)

**Subtitle** (30)
> Présentation PDF pour Beamer

**Keywords** (100 bytes)
> présentation,diapositives,notes,orateur,minuteur,télécommande,pointeur,LaTeX,cours,conférence

**Promotional text** (170)
> Présentez vos diapositives PDF avec notes, minuteur, pointeur et dessin. Contrôlez la présentation depuis votre iPhone, iPad ou Mac.

**Description** (4000)
> SlidePilot présente des diapositives PDF et est conçu pour les présentations LaTeX Beamer. Le public voit vos diapositives sur le projecteur ou l'écran externe ; vous voyez la diapositive actuelle, la suivante, vos notes et l'heure.
>
> VUE PRÉSENTATEUR
> • Diapositive actuelle, diapositive suivante et notes côte à côte, dans la disposition de votre choix
> • Horloge et chronomètre, ou minuteur avec deux alertes avant la fin du temps
> • Navigateur de diapositives avec miniatures et accès direct à chaque page
> • Écran noir ou blanc pour mettre la présentation en pause
>
> NOTES
> • Notes en texte enrichi pour chaque diapositive
> • Notes Beamer sur le second écran : SlidePilot vous montre la moitié notes de chaque page et au public la moitié diapositive, et détecte la position grâce aux mots-clés PDF SP-Right, SP-Left, SP-Top et SP-Bottom
> • Les notes, dessins et réglages restent associés à chaque PDF et peuvent être exportés dans un fichier .slidepilot
>
> POINTEUR ET DESSIN
> • Un pointeur sur l'écran du public : point, cercle, cible, curseur ou votre propre modèle
> • Dessinez sur la diapositive actuelle avec la souris, le doigt ou l'Apple Pencil ; gardez les dessins ou exportez-les en PDF
>
> CONÇU POUR LATEX
> • Rechargement automatique quand vous recompilez le PDF, sur la même diapositive
> • Les liens internes, les liens web et les vidéos intégrées avec Beamer fonctionnent pendant l'exposé
>
> TÉLÉCOMMANDE
> • Contrôlez une présentation sur Mac ou iPad depuis votre iPhone, ou depuis tout autre appareil avec SlidePilot
> • Les appareils s'associent une fois avec un code affiché sur les deux écrans ; la connexion est chiffrée
>
> SUR TOUS VOS APPAREILS
> • Une seule app pour Mac, iPad et iPhone, avec écran externe par câble ou AirPlay
> • Raccourcis clavier et télécommandes de présentation, VoiceOver, taille du texte dynamique, mode sombre
> • Français, anglais et allemand
>
> SLIDEPILOT PRO
> SlidePilot est gratuit. Tout ce qui se passe sur votre propre écran est illimité : ouvrir des PDF, la vue présentateur, les notes, le minuteur, le pointeur et le dessin. La présentation sur un écran pour le public et la télécommande peuvent être essayées 3 minutes à chaque fois. L'achat intégré unique SlidePilot Pro les débloque sans limite sur tous vos appareils, et pour votre famille grâce au partage familial.
>
> SlidePilot est open source. Pas de compte, pas de suivi, aucune donnée collectée.

**What's New** (4000)
> SlidePilot 2.0 est une réécriture complète pour macOS, iPadOS et, pour la première fois, iPhone.
> • Nouveau : télécommande entre deux appareils quelconques avec SlidePilot, associés par un code et chiffrés
> • Nouveau : plusieurs PDF ouverts à la fois, chacun avec ses propres fenêtres présentateur et présentation
> • Nouveau : les notes, dessins et réglages restent associés à chaque PDF et peuvent être exportés dans un fichier .slidepilot
> • Nouveau : minuteur avec deux alertes, listes automatiques dans les notes, prise en charge de l'Apple Pencil
> • Design natif pour macOS 26 et iPadOS 26, avec VoiceOver, taille du texte dynamique et mode sombre

## App privacy (App Store Connect ▸ App Privacy)

- **Data collection:** "No, we do not collect data from this app." Result: **Data Not Collected**.
- Why this is correct: the app has no server, no analytics, no crash reporting of its own and no third-party SDKs. PDFs, notes, drawings and settings stay on the device (app container, ADR 0012). The remote connects two devices on the local network directly; nothing passes through a server of the developer (ADR 0017). Purchases are handled by the App Store; the app only reads its own entitlement. `PrivacyInfo.xcprivacy` declares no tracking and no collected data.
- Crash reports and usage data that users share with developers through Apple are collected by Apple, not by the app, and do not need to be declared.

## Accessibility Nutrition Labels

From the [accessibility audit](accessibility-audit.md), for macOS and iOS (iPad and iPhone). Declare a feature only after the audit's manual checks 1–3 passed on real devices.

| Feature | Mac | iPad, iPhone |
|---|---|---|
| VoiceOver | Yes | Yes |
| Voice Control | Yes | Yes |
| Larger Text | – (the Mac has no system text size) | Yes |
| Dark Interface | Yes | Yes |
| Differentiate Without Color Alone | Yes | Yes |
| Sufficient Contrast | Yes | Yes |
| Reduced Motion | Yes | Yes |
| Captions | Not applicable (the app plays only the presenter's own videos) | Not applicable |
| Audio Descriptions | Not applicable | Not applicable |

## Export compliance

`ITSAppUsesNonExemptEncryption = NO`; no export documentation. Reasoning in [`release.md`](release.md#what-each-build-contains) ("Export compliance").

## App Review information

**Sign-in:** not required (no account).

**Notes for App Review** (English only):
> SlidePilot is a presenter for PDF slides. Open any PDF to see the presenter view (current slide, next slide, notes, timer).
> Audience output: connect an external display or use AirPlay (iPad, iPhone); on the Mac, choose Presentation ▸ Start Presentation. Without the in-app purchase "SlidePilot Pro" this output and remote control run as a 3-minute trial with a "SlidePilot – Trial Version" banner; afterwards the purchase offer appears. The offer is also in Settings ▸ SlidePilot Pro, with Restore Purchases.
> Remote control needs a second device with SlidePilot on the same network: Settings ▸ Remote on both devices, then confirm the same 6-digit code on both. The app uses the local network only for this; there is no server.

## Screenshots

Made from the fixtures only, in each language, light mode, kept outside the repository. Required sets (App Store Connect screenshot specifications, checked 2026-11-25; up to 10 per size and language, PNG or JPEG without alpha):

| Device | Size (pixels) | Required |
|---|---|---|
| Mac | 2880 × 1800 (16:10) | Yes |
| iPad 13-inch | 2064 × 2752 or 2752 × 2064 | Yes |
| iPhone 6.9-inch | 1320 × 2868 or 2868 × 1320 | Yes (6.5-inch then not needed) |
| iPhone Duo outer display | 1398 × 2034 or 2034 × 1398 | Optional; required from April 2027 for builds with the iOS 27.1 SDK |
| iPhone Duo inner display | 2007 × 2853 or 2853 × 2007 | Optional; earns the iPhone Duo badge |
