import QtQuick
import QtQuick.Effects
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "AppleMusicModel.js" as Model

BarWidget {
  id: root
  moduleName: "is.geir.apple-music"

  readonly property var music: bar && bar.shell
    ? bar.shell.serviceFor("is.geir.apple-music") : null
  readonly property string barDisplay: String(setting("barDisplay", "Artwork"))
  readonly property bool artworkDisplay: barDisplay !== "Text"
  readonly property bool showArtist: setting("showArtist", true)
  readonly property real maxLabelWidth: setting("maxLabelWidth", 220)
  readonly property bool showQueue: setting("showQueue", true)
  readonly property bool showRecentlyPlayed: setting("showRecentlyPlayed", true)
  readonly property bool showPlaybackModes: setting("showPlaybackModes", true)
  // Nerd Font nf-md glyphs, resolved from CaskaydiaMono Nerd Font's cmap:
  // md-heart, md-heart_outline, md-thumb_down, md-thumb_down_outline
  readonly property string heartIcon: String.fromCodePoint(0xf02d1)
  readonly property string heartOutlineIcon: String.fromCodePoint(0xf02d5)
  readonly property string thumbDownIcon: String.fromCodePoint(0xf0511)
  readonly property string thumbDownOutlineIcon: String.fromCodePoint(0xf0512)
  // Checked by rendering the Nerd Font: shuffle f049d, repeat f0456,
  // repeat_once f0458, repeat_off f0457, infinity f06e4 (Apple Music's
  // autoplay mark), clock_outline f0150, alert f0026. Upstream's code points
  // drew a quote bubble, restore/reply/reply-all arrows, and library-add.
  readonly property string shuffleIcon: String.fromCodePoint(0xf049d)
  readonly property string repeatIcon: String.fromCodePoint(0xf0456)
  readonly property string repeatOnceIcon: String.fromCodePoint(0xf0458)
  readonly property string repeatOffIcon: String.fromCodePoint(0xf0457)
  readonly property string plusIcon: String.fromCodePoint(0xf0415)
  readonly property string checkIcon: String.fromCodePoint(0xf012c)
  readonly property string clockOutlineIcon: String.fromCodePoint(0xf0150)
  readonly property string alertIcon: String.fromCodePoint(0xf0026)
  readonly property string autoplayIcon: String.fromCodePoint(0xf06e4)
  readonly property color popupForeground: bar ? bar.foreground : Color.foreground
  readonly property string popupFontFamily: bar ? bar.fontFamily : Style.font.family
  // Last non-empty track details. Chromium blanks the metadata for ~0.5s
  // between tracks; showing these instead keeps the previous song on screen
  // until the next one is known. Empty only before anything has played.
  property string shownTitle: ""
  property string shownArtist: ""
  property string shownAlbum: ""

  function adoptTrackDetails() {
    if (!music || music.title === "") return
    shownTitle = music.title
    shownArtist = music.artist
    shownAlbum = music.album
    adoptPreloadedCover(music.title, music.artist)
    checkBackAlbum()
  }

  // The held cover/details only bridge the gap between songs. When the Apple
  // Music player goes away (window closed), drop them so the bar returns to
  // the Apple Music logo instead of showing the last song forever.
  function forgetTrack() {
    shownTitle = ""
    shownArtist = ""
    shownAlbum = ""
    readyArtUrl = ""
    readyHiResUrl = ""
    readyHiResTitle = ""
    knownEntries = []
    shownUpNext = []
    heldCredits = null
    heldCreditsTitle = ""
    pendingCredits = null
  }

  // Shows the predicted next/previous track the instant it is clicked.
  function adoptPrediction() {
    var entry = music ? music.predictedTrack : null
    if (!entry) return
    shownTitle = entry.title
    shownArtist = entry.artist || ""
    shownAlbum = entry.album || ""
    adoptPreloadedCover(entry.title, entry.artist)
    checkBackAlbum()
  }

  // Queue entries (with cover URLs) from the last time the bridge matched.
  // The live queue disappears during a track change, which is exactly when
  // the covers are needed.
  property var knownEntries: []
  // Cover URLs already decoded into the pixmap cache by the preloaders.
  property var preloadedUrls: ({})

  // Last known up-next list, held through track changes like the details.
  property var shownUpNext: []

  function rememberQueue() {
    if (!music || !music.bridgeActive) return
    shownUpNext = music.upNext
    var entries = music.upNext.slice(0, 3)
    if (music.previousTrack) entries.push(music.previousTrack)
    if (entries.length > 0) knownEntries = entries
  }

  function adoptPreloadedCover(title, artist) {
    var candidates = knownEntries.concat(music && music.predictedTrack ? [music.predictedTrack] : [])
    for (var i = 0; i < candidates.length; i++) {
      var entry = candidates[i]
      if (entry.title !== title || (artist && entry.artist && entry.artist !== artist)) continue
      if (entry.artworkUrl && preloadedUrls[entry.artworkUrl]) {
        readyHiResUrl = entry.artworkUrl
        readyHiResTitle = title
      }
      return
    }
  }

  Connections {
    target: root.music
    ignoreUnknownSignals: true
    function onTitleChanged() { root.adoptTrackDetails() }
    function onArtistChanged() { root.adoptTrackDetails() }
    function onAlbumChanged() { root.adoptTrackDetails() }
    function onPredictedTrackChanged() { root.adoptPrediction() }
    function onAvailableChanged() { if (!root.music.available) root.forgetTrack() }
    function onCreditsChanged() { root.receiveCredits(root.music.credits, root.music.title) }
    function onUpNextChanged() { root.rememberQueue() }
    function onPreviousTrackChanged() { root.rememberQueue() }
  }

  // Pre-load the covers of the next two tracks and the previous one so a
  // track change can swap covers in the same frame as the title.
  Repeater {
    model: root.knownEntries

    Image {
      required property var modelData
      visible: false
      asynchronous: true
      source: modelData.artworkUrl || ""
      onStatusChanged: if (status === Image.Ready) {
        var urls = root.preloadedUrls
        urls[String(source)] = true
        root.preloadedUrls = urls
      }
    }
  }

  // Chromium also reports "not playing" for the ~0.5s gap between tracks,
  // so the paused overlay only appears once a pause has lasted a moment.
  readonly property bool pausedNow: !!music && music.hasMedia && !music.playing
  property bool showPaused: false
  onPausedNowChanged: {
    if (pausedNow) pausedDelay.restart()
    else { pausedDelay.stop(); showPaused = false }
  }
  Timer {
    id: pausedDelay
    interval: 900
    onTriggered: root.showPaused = root.pausedNow
  }

  Component.onCompleted: {
    adoptTrackDetails()
    showPaused = pausedNow
  }
  onMusicChanged: adoptTrackDetails()

  readonly property string trackLabel: {
    if (shownTitle === "" && shownArtist === "") return "Music"
    if (showArtist && shownArtist) return shownArtist + " — " + shownTitle
    return shownTitle || shownArtist
  }
  readonly property string tooltipLabel: {
    if (shownTitle && shownArtist) return shownTitle + " — " + shownArtist
    return shownTitle || shownArtist || "Apple Music"
  }
  readonly property string playbackIcon: music && music.playing ? "󰏤" : "󰐊"

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  readonly property bool tooltipHovered: visible && opacity > 0 && barMouseArea.containsMouse

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  // Fixed row counts so the popup keeps one height across track changes.
  readonly property int queueSlots: 6
  readonly property int recentSlots: 5

  // Corner radius from the theme (Hyprland decoration:rounding), capped so
  // small items never turn into circles.
  function themeRadius(size) { return Math.min(Style.cornerRadius, size / 2) }

  // Popup artwork state: 0 = thumbnail beside the details, 1 = full-width
  // square cover header, 2 = the same square flipped to the album back.
  property int coverMode: 0
  // Cover motion: resizing (and the details' slide) is quick; turning
  // between front and back is slower. Shrinking from the back turns at the
  // quick speed so it stays one snappy motion.
  readonly property int resizeMotion: 200
  readonly property int flipMotion: 450
  readonly property bool largeArtwork: coverMode > 0

  // Nerd Font md glyphs (rendered and checked): arrow_top_right,
  // arrow_bottom_left, information_outline, album.
  readonly property string enlargeIcon: String.fromCodePoint(0xf005c)
  readonly property string shrinkIcon: String.fromCodePoint(0xf0042)
  readonly property string creditsIcon: String.fromCodePoint(0xf02fd)
  readonly property string coverIcon: String.fromCodePoint(0xf0025)

  // Tooltips for the cover's corner icons. The shell Button shows its
  // tooltip after a fixed 400ms, which is intrusive over artwork where the
  // pointer rests; these wait 800ms, then stay "warm" for 1s so moving to
  // the other corner icon shows its tip at once (macOS-style).
  property bool coverTipsWarm: false

  Timer {
    id: coverTipsCool
    interval: 1000
    onTriggered: root.coverTipsWarm = false
  }

  component CoverTip: QQC.ToolTip {
    id: coverTip
    required property Item target
    parent: target
    visible: target.visible && target.hot
    delay: root.coverTipsWarm ? 0 : 800
    padding: 0
    onVisibleChanged: {
      if (visible) { root.coverTipsWarm = true; coverTipsCool.stop() }
      else coverTipsCool.restart()
    }
    background: BorderSurface {
      color: Color.tooltip.background
      borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Color.tooltip.border,
        Color.tooltip.border, Math.max(1, Style.normalBorderWidth))
      radius: 0
    }
    contentItem: Text {
      textFormat: Text.PlainText
      text: coverTip.text
      color: Color.tooltip.text
      font.family: root.popupFontFamily
      font.pixelSize: Style.font.bodySmall
      leftPadding: Style.spacing.controlPaddingX + Math.max(1, Style.normalBorderWidth)
      rightPadding: Style.spacing.controlPaddingX + Math.max(1, Style.normalBorderWidth)
      topPadding: Style.spacing.controlPaddingY + Math.max(1, Style.normalBorderWidth)
      bottomPadding: Style.spacing.controlPaddingY + Math.max(1, Style.normalBorderWidth)
    }
  }

  function setCoverMode(mode) {
    if (mode === 2) backScroll.contentY = 0
    coverMode = mode
  }

  // With the back open, a track from the same album keeps the back (its
  // song credits update in place); a different album turns it over to the
  // new cover. The old back stays on its face while it turns away, so new
  // credits are applied only once the flip has finished.
  function normalizedAlbum(name) {
    return String(name || "").toLowerCase().replace(/ - (single|ep)$/, "").trim()
  }

  function turnToFront() {
    if (coverMode !== 2) return
    coverMode = 1
    flipSettle.restart()
  }

  function checkBackAlbum() {
    if (coverMode !== 2 || !heldCredits || !heldCredits.album || !shownAlbum) return
    if (normalizedAlbum(shownAlbum) !== normalizedAlbum(heldCredits.album)) turnToFront()
  }

  property var pendingCredits: null
  property string pendingCreditsTitle: ""

  function applyCredits(credits, title) {
    heldCredits = credits
    heldCreditsTitle = title
    creditsGrace = false
  }

  function receiveCredits(credits, title) {
    if (!credits) return
    var otherAlbum = heldCredits && credits.albumId && heldCredits.albumId
      && credits.albumId !== heldCredits.albumId
    if (coverMode === 2 && otherAlbum) turnToFront()
    if (flipSettle.running) {
      pendingCredits = credits
      pendingCreditsTitle = title
      return
    }
    applyCredits(credits, title)
  }

  Timer {
    id: flipSettle
    interval: root.flipMotion + 30
    onTriggered: if (root.pendingCredits) {
      root.applyCredits(root.pendingCredits, root.pendingCreditsTitle)
      root.pendingCredits = null
    }
  }

  // Album-back details, held through track changes like the other details
  // and only shown for the song they belong to.
  property var heldCredits: null
  property string heldCreditsTitle: ""
  // After a track change the previous back stays up (creditsGrace) until
  // the new song's credits arrive, so the back swaps once instead of
  // flashing the fallback. Usually instant: the page prefetches the next and
  // previous songs' credits.
  property bool creditsGrace: false
  readonly property var backCredits:
    heldCredits && (heldCreditsTitle === shownTitle || creditsGrace) ? heldCredits : null

  onShownTitleChanged: {
    if (heldCredits && heldCreditsTitle !== shownTitle) {
      creditsGrace = true
      creditsGraceTimer.restart()
    }
  }

  Timer {
    id: creditsGraceTimer
    interval: 3000
    onTriggered: {
      root.creditsGrace = false
      // No credits arrived for the new song: show its cover, not a fallback.
      if (root.heldCreditsTitle !== root.shownTitle) root.turnToFront()
    }
  }

  // Colours ease between albums' palettes instead of snapping.
  property color backBackground: backCredits && backCredits.background
    ? backCredits.background : Qt.tint(Color.popups.background, Util.alpha(popupForeground, 0.06))
  property color backText: backCredits && backCredits.text ? backCredits.text : popupForeground
  property color backTextSecondary: backCredits && backCredits.textSecondary
    ? backCredits.textSecondary : Util.alpha(popupForeground, 0.75)
  property color backTextTertiary: backCredits && backCredits.textTertiary
    ? backCredits.textTertiary : Util.alpha(popupForeground, 0.55)
  Behavior on backBackground { ColorAnimation { duration: 300 } }
  Behavior on backText { ColorAnimation { duration: 300 } }
  Behavior on backTextSecondary { ColorAnimation { duration: 300 } }
  Behavior on backTextTertiary { ColorAnimation { duration: 300 } }
  readonly property string backMetaLine: {
    if (!backCredits) return ""
    var parts = []
    if (backCredits.releaseDate) parts.push(backCredits.releaseDate.slice(0, 4))
    if (backCredits.label) parts.push(backCredits.label)
    if (backCredits.trackNumber > 0) parts.push(backCredits.trackCount > 0
      ? "Track " + backCredits.trackNumber + " of " + backCredits.trackCount
      : "Track " + backCredits.trackNumber)
    if (backCredits.genre) parts.push(backCredits.genre)
    parts = parts.concat(backCredits.traits || [])
    return parts.join(" · ")
  }
  // Apple Music brand red, used for progress so it never blends into the
  // theme accent (e.g. the bar's open-indicator line).
  readonly property color appleMusicRed: "#FA243C"

  // Last artwork URL that decoded successfully. Chromium hands MPRIS a new
  // /tmp artwork file several times per track switch and deletes the old
  // ones, so binding an Image straight to artUrl flashes placeholders. The
  // visible images keep painting readyArtUrl until the new URL finishes
  // loading in the probe below.
  property string readyArtUrl: ""

  // Omarchy's draggable bar wrapper uses this contract both to dispatch
  // clicks and to decide whether the slot should show a pointing cursor.
  function triggerPress(button) {
    if (!music) return
    if (button === Qt.MiddleButton && music.available) music.togglePlayback()
    else if (!music.available) music.openAppleMusic()
    else toggle()
  }

  implicitWidth: vertical
    ? barSize
    : (artworkDisplay ? Style.bar.iconSlot : textRow.implicitWidth + Style.space(14))
  implicitHeight: vertical && artworkDisplay ? Style.bar.iconSlot : barSize

  Item {
    id: artworkPuck
    anchors.centerIn: parent
    width: root.vertical ? root.barSize : Style.bar.iconSlot
    height: root.vertical ? Style.bar.iconSlot : root.barSize
    visible: root.artworkDisplay

    readonly property real canvasSize: Math.max(
      Style.bar.iconCanvas,
      Math.min(Style.space(20), Math.min(width, height) - Style.space(6)))

    Rectangle {
      id: artworkMask
      width: artworkPuck.canvasSize
      height: width
      radius: root.themeRadius(width)
      visible: false
      layer.enabled: true
      color: "white"
    }

    // Render the SVG once at physical resolution and colorize it outside the
    // album-art mask. Keeping this to one effect avoids the softened edges
    // caused by routing the logo through both colorization and artwork masks.
    Image {
      id: themedLogoSource
      anchors.centerIn: parent
      width: Style.bar.iconFont
      height: width
      source: Qt.resolvedUrl("assets/apple-music-monochrome.svg")
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: themedLogoSource
      source: themedLogoSource
      visible: root.popupArtUrl === ""
      colorization: 1.0
      colorizationColor: root.popupForeground
    }

    Item {
      id: artworkSurface
      anchors.centerIn: parent
      width: artworkPuck.canvasSize
      height: width
      visible: root.popupArtUrl !== ""
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: artworkMask
        maskThresholdMin: 0.3
        maskSpreadAtMin: 0.1
      }

      Image {
        id: puckArtwork
        anchors.fill: parent
        source: root.popupArtUrl
        fillMode: Image.PreserveAspectCrop
        // A probe or preloader already decoded this URL; loading it
        // synchronously from the cache swaps covers with no empty gap.
        asynchronous: false
        cache: true
        smooth: true
      }

      Rectangle {
        anchors.fill: parent
        visible: root.showPaused
        color: Util.alpha(Color.bar.background, 0.45)
      }

      OpticalGlyph {
        anchors.centerIn: parent
        width: Style.space(10)
        height: width
        visible: root.showPaused
        text: "󰐊"
        color: Color.bar.text
        fontFamily: root.bar ? root.popupFontFamily : Style.font.family
        fontSize: Style.font.caption
      }

      Rectangle {
        id: puckProgressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(1, Style.space(2))
        // Hidden while the popup is open, which shows its own progress bar.
        visible: !!root.music && root.music.hasMedia && root.music.hasValidLength
          && !root.opened
        color: Util.alpha(Color.bar.background, 0.6)

        Rectangle {
          width: parent.width * (root.music ? root.music.progress : 0)
          height: parent.height
          color: root.appleMusicRed
        }
      }
    }
  }

  Row {
    id: textRow
    anchors.centerIn: parent
    spacing: Style.space(6)
    visible: !root.artworkDisplay

    Item {
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -1.5

      OpticalGlyph {
        anchors.fill: parent
        text: ""
        color: root.bar ? root.bar.barForeground : Color.foreground
        fontFamily: root.bar ? root.popupFontFamily : Style.font.family
        fontSize: Style.bar.iconFont
      }
    }

    Item {
      width: Math.min(root.maxLabelWidth, label.implicitWidth)
      height: label.implicitHeight
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical

      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -0.5
        text: root.trackLabel
        textFormat: Text.PlainText
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.popupFontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: Math.min(root.maxLabelWidth, implicitWidth)
      }
    }
  }

  MouseArea {
    id: barMouseArea
    anchors.fill: parent
    hoverEnabled: true
    Accessible.role: Accessible.Button
    Accessible.name: !root.music || !root.music.hasMedia
      ? "Open Apple Music"
      : "Apple Music: " + root.tooltipLabel + (root.music.playing ? ", playing" : ", paused")
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    onClicked: function(mouse) { root.triggerPress(mouse.button) }
    onWheel: function(wheel) {
      if (!root.music || !root.music.available) return
      if (wheel.angleDelta.y > 0) root.music.previous()
      else if (wheel.angleDelta.y < 0) root.music.next()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipLabel)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Image {
    id: artworkProbe
    visible: false
    asynchronous: true
    cache: false
    source: root.music ? root.music.artUrl : ""
    // Never cleared: during a track change MPRIS briefly reports no artwork,
    // so the previous cover stays up until the next one has decoded. The
    // placeholder only shows before anything has played.
    onStatusChanged: if (status === Image.Ready) root.readyArtUrl = String(source)
  }

  // Large cover from Apple's CDN. Kept on screen until the next track's
  // cover (large or thumbnail) is ready, so track changes swap covers once
  // instead of stepping through a blurry thumbnail.
  property string readyHiResUrl: ""
  property string readyHiResTitle: ""
  readonly property string popupArtUrl: readyHiResUrl !== "" ? readyHiResUrl : readyArtUrl

  onReadyArtUrlChanged: {
    if (!music || readyHiResTitle !== music.title) {
      readyHiResUrl = ""
      readyHiResTitle = ""
    }
  }

  Image {
    id: hiResProbe
    visible: false
    asynchronous: true
    source: root.music ? root.music.hiResArtUrl : ""
    onStatusChanged: if (status === Image.Ready && root.music) {
      var urls = root.preloadedUrls
      urls[String(source)] = true
      root.preloadedUrls = urls
      root.readyHiResUrl = String(source)
      root.readyHiResTitle = root.music.title
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(12)

      // Header with two artwork states: a small thumbnail beside the track
      // details, or a full-width square cover above them. Clicking the cover
      // switches between them. Geometry is fixed per state so track changes
      // never resize the popup.
      Item {
        id: header
        width: parent.width
        // Follows the animated cover and details, so the popup grows and
        // shrinks smoothly with them.
        height: Math.max(cover.height, details.y + details.height)

        Item {
          id: cover
          x: 0
          y: 0
          width: root.largeArtwork ? header.width : Style.space(88)
          height: width
          // Same timing as the flip, so shrinking from the back turns and
          // scales down as one motion.
          Behavior on width {
            NumberAnimation { duration: root.resizeMotion; easing.type: Easing.OutCubic }
          }

          // Front: the cover. Back: the album back (credits, label, release),
          // tinted with the album's own palette. Click cycles small → large →
          // back → small.
          Flipable {
            id: coverFlip
            anchors.fill: parent

            front: Item {
              anchors.fill: parent

              // Placeholder surface behind a missing cover; no border.
              Rectangle {
                anchors.fill: parent
                radius: root.themeRadius(width)
                color: Util.alpha(root.popupForeground, 0.06)
                visible: root.popupArtUrl === ""
              }

              Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: root.themeRadius(width)
                visible: false
                layer.enabled: true
                color: "white"
              }

              // Loaded synchronously from the pixmap cache: a probe has already
              // decoded this URL, so the previous cover stays on screen until the
              // new one paints instead of flashing the placeholder glyph.
              Image {
                id: artwork
                anchors.fill: parent
                source: root.popupArtUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                smooth: true
                layer.enabled: root.themeRadius(width) > 0
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: coverMask
                  maskThresholdMin: 0.3
                  maskSpreadAtMin: 0.1
                }
              }

              Text {
                anchors.centerIn: parent
                visible: root.popupArtUrl === ""
                text: "󰝚"
                color: root.popupForeground
                font.family: root.popupFontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            back: Rectangle {
              anchors.fill: parent
              radius: root.themeRadius(width)
              color: root.backBackground
              clip: true

              Flickable {
                id: backScroll
                anchors.fill: parent
                anchors.margins: Style.space(14)
                contentHeight: backColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: root.coverMode === 2

                Column {
                  id: backColumn
                  width: backScroll.width
                  spacing: Style.space(10)

                  Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: root.backCredits && root.backCredits.album
                        ? root.backCredits.album : (root.shownAlbum || root.shownTitle)
                      textFormat: Text.PlainText
                      color: root.backText
                      font.family: root.popupFontFamily
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      width: parent.width
                      text: root.backCredits && root.backCredits.artist
                        ? root.backCredits.artist : root.shownArtist
                      textFormat: Text.PlainText
                      color: root.backTextSecondary
                      font.family: root.popupFontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      width: parent.width
                      visible: text !== ""
                      text: root.backMetaLine
                      textFormat: Text.PlainText
                      color: root.backTextTertiary
                      font.family: root.popupFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                  }

                  Repeater {
                    model: root.backCredits ? root.backCredits.categories : []

                    Column {
                      id: creditGroup
                      required property var modelData
                      width: backColumn.width
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        text: creditGroup.modelData.title
                        textFormat: Text.PlainText
                        color: root.backTextTertiary
                        font.family: root.popupFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1
                      }

                      Repeater {
                        model: creditGroup.modelData.people

                        Text {
                          required property var modelData
                          width: creditGroup.width
                          text: modelData.name + (modelData.roles ? " — " + modelData.roles : "")
                          textFormat: Text.PlainText
                          color: root.backText
                          font.family: root.popupFontFamily
                          font.pixelSize: Style.font.caption
                          wrapMode: Text.WordWrap
                        }
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: !root.backCredits || root.backCredits.categories.length === 0
                    text: root.backCredits ? "No credits for this song" : "Credits unavailable"
                    textFormat: Text.PlainText
                    color: root.backTextTertiary
                    font.family: root.popupFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.backCredits ? root.backCredits.copyright : ""
                    textFormat: Text.PlainText
                    color: root.backTextTertiary
                    font.family: root.popupFontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }

            transform: Rotation {
              origin.x: coverFlip.width / 2
              origin.y: coverFlip.height / 2
              axis { x: 0; y: 1; z: 0 }
              angle: root.coverMode === 2 ? 180 : 0

              Behavior on angle {
                NumberAnimation {
                  duration: root.coverMode === 0 ? root.resizeMotion : root.flipMotion
                  easing.type: root.coverMode === 0 ? Easing.OutCubic : Easing.InOutCubic
                }
              }
            }
          }

          // A click anywhere does what the top-right icon shows: small →
          // large, large → album back, back → cover. Wheel events pass
          // through to the back's scroll area; only clicks are taken here.
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            Accessible.role: Accessible.Button
            Accessible.name: root.coverMode === 0 ? "Enlarge artwork"
              : root.coverMode === 1 ? "Show album credits" : "Show cover"
            onClicked: root.setCoverMode(root.coverMode === 1 ? 2 : 1)
          }

          HoverHandler { id: coverHover }

          // Corner icons, revealed while the cover is hovered; each has the
          // shell's tooltip. Top right: the click action. Bottom left: shrink.
          Button {
            id: coverPrimaryIcon
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(6)
            width: Style.space(24)
            height: Style.space(24)
            iconText: root.coverMode === 0 ? root.enlargeIcon
              : root.coverMode === 1 ? root.creditsIcon : root.coverIcon
            iconSize: Style.font.caption
            foreground: root.popupForeground
            background: Util.alpha(Color.popups.background, 0.75)
            readonly property string tip: root.coverMode === 0 ? "Enlarge"
              : root.coverMode === 1 ? "Album credits" : "Show cover"
            Accessible.name: tip
            opacity: coverHover.hovered ? (hot ? 1 : 0.85) : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            onClicked: root.setCoverMode(root.coverMode === 1 ? 2 : 1)

            CoverTip { target: coverPrimaryIcon; text: coverPrimaryIcon.tip }
          }

          Button {
            id: coverShrinkIcon
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(6)
            width: Style.space(24)
            height: Style.space(24)
            iconText: root.shrinkIcon
            iconSize: Style.font.caption
            foreground: root.popupForeground
            background: Util.alpha(Color.popups.background, 0.75)
            Accessible.name: "Shrink"
            opacity: root.coverMode > 0 && coverHover.hovered ? (hot ? 1 : 0.85) : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            onClicked: root.setCoverMode(0)

            CoverTip { target: coverShrinkIcon; text: "Shrink" }
          }
        }

        Column {
          id: details
          // Targets use the cover's final size, not its animating one, so
          // each slide is a single animation instead of re-aiming per frame.
          x: root.largeArtwork ? 0 : Style.space(88) + Style.space(12)
          y: root.largeArtwork
            ? header.width + Style.space(12)
            : Math.max(0, (Style.space(88) - height) / 2)
          width: header.width - x
          spacing: Style.space(4)
          Behavior on x {
            NumberAnimation { duration: root.resizeMotion; easing.type: Easing.OutCubic }
          }
          Behavior on y {
            NumberAnimation { duration: root.resizeMotion; easing.type: Easing.OutCubic }
          }

          // Every line always reserves its height, even when empty.
          Text {
            width: parent.width
            text: root.shownTitle || "Apple Music"
            textFormat: Text.PlainText
            color: root.popupForeground
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.shownArtist || " "
            textFormat: Text.PlainText
            color: Util.alpha(root.popupForeground, 0.75)
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.shownAlbum || " "
            textFormat: Text.PlainText
            color: Util.alpha(root.popupForeground, 0.55)
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        // Always shown (dimmed when idle) so the popup height never changes.
        opacity: !!root.music && root.music.available ? 1 : 0.4

        Rectangle {
          id: progressTrack
          width: parent.width
          height: Style.space(5)
          radius: root.themeRadius(height)
          color: Util.alpha(root.popupForeground, 0.2)

          Rectangle {
            width: parent.width * (root.music ? root.music.progress : 0)
            height: parent.height
            radius: parent.radius
            color: root.appleMusicRed
          }

          MouseArea {
            anchors.fill: parent
            enabled: !!root.music && root.music.canSeek
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: function(mouse) { root.music.seekFraction(mouse.x / width) }
          }
        }

        Row {
          width: parent.width

          Text {
            id: elapsed
            text: root.music ? root.music.elapsedText : "0:00"
            color: Util.alpha(root.popupForeground, 0.65)
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.caption
          }

          Item { width: parent.width - elapsed.implicitWidth - duration.implicitWidth; height: 1 }

          Text {
            id: duration
            text: root.music ? root.music.lengthText : "--:--"
            color: Util.alpha(root.popupForeground, 0.65)
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(8)

        Button {
          width: Style.space(44)
          height: Style.space(40)
          iconText: "󰒮"
          foreground: root.popupForeground
          enabled: !!root.music && root.music.available && root.music.activePlayer.canGoPrevious
          opacity: enabled ? 1 : 0.4
          onClicked: root.music.previous()
        }

        Button {
          width: Style.space(44)
          height: Style.space(40)
          iconText: root.playbackIcon
          foreground: root.popupForeground
          iconSize: Style.font.iconLarge
          enabled: !!root.music && root.music.available
          opacity: enabled ? 1 : 0.4
          onClicked: root.music.togglePlayback()
        }

        Button {
          width: Style.space(44)
          height: Style.space(40)
          iconText: "󰒭"
          foreground: root.popupForeground
          enabled: !!root.music && root.music.available && root.music.activePlayer.canGoNext
          opacity: enabled ? 1 : 0.4
          onClicked: root.music.next()
        }
      }

      // Compact secondary controls: ratings/library and playback modes share
      // one row, separated visually, so the popup keeps transport prominent
      // without spending three full rows on nine actions.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          width: Style.space(36)
          height: Style.space(34)
          iconText: root.music && root.music.rating === "like"
            ? root.heartIcon : root.heartOutlineIcon
          foreground: root.music && root.music.rating === "like"
            ? Color.accent : root.popupForeground
          enabled: !!root.music && root.music.bridgeActive
          opacity: enabled ? 1 : 0.4
          tooltipText: "Like"
          Accessible.name: "Like current song"
          onClicked: root.music.toggleLike()
        }

        Button {
          width: Style.space(36)
          height: Style.space(34)
          iconText: root.music && root.music.rating === "dislike"
            ? root.thumbDownIcon : root.thumbDownOutlineIcon
          foreground: root.music && root.music.rating === "dislike"
            ? Color.accent : root.popupForeground
          enabled: !!root.music && root.music.bridgeActive
          opacity: enabled ? 1 : 0.4
          tooltipText: "Suggest less"
          Accessible.name: "Suggest less like the current song"
          onClicked: root.music.toggleDislike()
        }

        Button {
          width: Style.space(36)
          height: Style.space(34)
          iconText: !root.music || root.music.libraryState === "unknown" ? root.plusIcon
            : root.music.libraryState === "absent" ? root.plusIcon
            : root.music.libraryState === "adding" ? root.clockOutlineIcon
            : root.music.libraryState === "present" ? root.checkIcon : root.alertIcon
          foreground: root.music && root.music.libraryState === "present"
            ? Color.accent : root.popupForeground
          enabled: !!root.music && root.music.libraryState === "absent"
          opacity: enabled ? 1 : 0.4
          tooltipText: !root.music || root.music.libraryState === "unknown"
            ? "Library state unavailable"
            : root.music.libraryState === "absent" ? "Add to library"
            : root.music.libraryState === "adding" ? "Adding to library"
            : root.music.libraryState === "present" ? "In your library"
            : "Couldn't add to library"
          Accessible.name: !root.music || root.music.libraryState === "unknown"
            ? "Library state unavailable"
            : root.music.libraryState === "absent" ? "Add current song to library"
            : root.music.libraryState === "adding" ? "Adding current song to library"
            : root.music.libraryState === "present" ? "Current song is in your library"
            : "Couldn't add to library"
          onClicked: root.music.addToLibrary()
        }

        Rectangle {
          width: 1
          height: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.showPlaybackModes && !!root.music && root.music.bridgeActive
          color: Util.alpha(root.popupForeground, 0.18)
        }

        Button {
          width: Style.space(36)
          height: Style.space(34)
          visible: root.showPlaybackModes && !!root.music && root.music.bridgeActive
          iconText: root.shuffleIcon
          foreground: root.music && root.music.shuffleMode === true
            ? Color.accent : root.popupForeground
          enabled: !!root.music && root.music.shuffleMode !== null
          opacity: enabled ? 1 : 0.4
          tooltipText: "Shuffle"
          Accessible.name: "Shuffle"
          onClicked: root.music.setShuffle(root.music.shuffleMode !== true)
        }

        Button {
          width: Style.space(36)
          height: Style.space(34)
          visible: root.showPlaybackModes && !!root.music && root.music.bridgeActive
          iconText: !root.music || root.music.repeatMode === "all" ? root.repeatIcon
            : root.music.repeatMode === "one" ? root.repeatOnceIcon : root.repeatOffIcon
          foreground: root.music && (root.music.repeatMode === "all" || root.music.repeatMode === "one")
            ? Color.accent : root.popupForeground
          enabled: !!root.music && root.music.repeatMode !== "unknown"
          opacity: enabled ? 1 : 0.4
          tooltipText: root.music && root.music.repeatMode === "one"
            ? "Repeat one" : root.music && root.music.repeatMode === "all" ? "Repeat all" : "Repeat off"
          Accessible.name: tooltipText
          onClicked: root.music.cycleRepeat()
        }

        Button {
          width: Style.space(36)
          height: Style.space(34)
          visible: root.showPlaybackModes && !!root.music && root.music.bridgeActive
          iconText: root.autoplayIcon
          foreground: root.music && root.music.autoplay === true
            ? Color.accent : root.popupForeground
          enabled: !!root.music && root.music.autoplay !== null
          opacity: enabled ? 1 : 0.4
          tooltipText: "Autoplay"
          Accessible.name: "Autoplay"
          onClicked: root.music.setAutoplay(root.music.autoplay !== true)
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        // Fixed slot count so the popup keeps one height across track changes.
        visible: root.showQueue

        PanelSeparator { foreground: root.popupForeground }

        Text {
          width: parent.width
          text: "Up next"
          color: Util.alpha(root.popupForeground, 0.65)
          font.family: root.popupFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.queueSlots

          Item {
            id: queueRow
            required property int index
            readonly property var modelData: index < root.shownUpNext.length
              ? root.shownUpNext[index] : null
            width: parent.width
            height: queueLabel.implicitHeight + Style.space(4)

            Text {
              id: queueLabel
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - queueDuration.implicitWidth - Style.space(10)
              text: !queueRow.modelData ? " " : queueRow.modelData.title +
                (queueRow.modelData.artist ? " — " + queueRow.modelData.artist : "")
              textFormat: Text.PlainText
              color: root.popupForeground
              font.family: root.popupFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              id: queueDuration
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: queueRow.modelData && queueRow.modelData.durationSeconds > 0
                ? Model.formatTime(queueRow.modelData.durationSeconds) : ""
              color: Util.alpha(root.popupForeground, 0.55)
              font.family: root.popupFontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              enabled: !!queueRow.modelData
              cursorShape: Qt.PointingHandCursor
              onClicked: root.music.jumpToQueueIndex(queueRow.modelData.index)
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.showRecentlyPlayed

        PanelSeparator { foreground: root.popupForeground }

        Text {
          width: parent.width
          text: "Recently played"
          color: Util.alpha(root.popupForeground, 0.65)
          font.family: root.popupFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.recentSlots

          Item {
            id: historyRow
            required property int index
            readonly property var modelData: root.music && index < root.music.recentTracks.length
              ? root.music.recentTracks[index] : null
            width: parent.width
            height: historyLabel.implicitHeight + Style.space(4)

            Accessible.role: Accessible.ListItem
            Accessible.name: !historyRow.modelData ? "" : historyRow.modelData.title +
              (historyRow.modelData.artist ? " — " + historyRow.modelData.artist : "") +
              (historyRow.modelData.play ? ", replay" : ", open Apple Music")

            Text {
              id: historyLabel
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              text: !historyRow.modelData ? " " : historyRow.modelData.title +
                (historyRow.modelData.artist ? " — " + historyRow.modelData.artist : "")
              textFormat: Text.PlainText
              color: Util.alpha(root.popupForeground, 0.75)
              font.family: root.popupFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            MouseArea {
              anchors.fill: parent
              // Replayable rows carry an exact-song descriptor; legacy rows
              // keep the pre-existing focus behavior and must not imply replay.
              enabled: !!historyRow.modelData
              cursorShape: historyRow.modelData && historyRow.modelData.play
                ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: if (root.music) {
                if (historyRow.modelData.play) root.music.replayTrack(historyRow.modelData)
                else root.music.openAppleMusic()
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: openButton.height

        Button {
          id: openButton
          anchors.right: parent.right
          width: Style.space(28)
          height: Style.space(26)
          iconText: ""
          iconSize: Style.font.caption
          foreground: hot ? root.appleMusicRed : root.popupForeground
          opacity: hot ? 1 : 0.45
          tooltipText: root.music && root.music.bridgeActive
            ? "Show in Apple Music" : "Open Apple Music"
          Accessible.name: tooltipText
          onClicked: if (root.music) root.music.revealNowPlaying()
        }
      }
    }
  }
}
