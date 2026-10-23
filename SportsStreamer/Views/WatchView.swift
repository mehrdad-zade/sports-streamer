import SwiftUI

struct WatchView: View {
    let event: Event
    @Environment(AppSettings.self) private var settings
    @State private var session: WatchSession?

    var body: some View {
        Group {
            if let session {
                WatchContent(session: session)
            } else {
                Color.black
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let session = session ?? WatchSession(event: event, settings: settings)
            self.session = session
            session.start()
        }
        .onDisappear { session?.stop() }
    }
}

private struct WatchContent: View {
    let session: WatchSession
    @Environment(AppSettings.self) private var settings
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            video
                .frame(maxWidth: .infinity)
                .aspectRatio(isLandscape ? nil : 16 / 9, contentMode: .fit)
                .frame(maxHeight: isLandscape ? .infinity : nil)
                .background(.black)
                .overlay(alignment: .topTrailing) { if isLandscape { landscapeSourceMenu } }

            if !isLandscape { sourceList }
        }
        .ignoresSafeArea(edges: isLandscape ? .all : [])
        .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.switchToNextAlive() } label: { Image(systemName: "forward.end.fill") }
                    .disabled(session.nextAlive(after: session.currentID) == nil)
                    .accessibilityLabel("Next live source")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.monitor.recheckNow() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Re-check sources")
            }
        }
    }

    @ViewBuilder
    private var video: some View {
        if session.mode == .web, let source = session.currentSource {
            WebPlayerView(url: source.pageURL, referer: session.event.url)
        } else if session.currentSource?.isAlive == true {
            NativePlayerView(player: session.player.player)
                .overlay { if session.player.isBuffering { ProgressView().tint(.white).controlSize(.large) } }
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(.white).controlSize(.large)
                Text(searchStatus).font(.footnote).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private var searchStatus: String {
        let monitor = session.monitor
        if monitor.isLoadingSources { return "Opening event page…" }
        if monitor.sources.isEmpty { return "No sources found" }
        return "Finding a live stream… checked \(monitor.checkedCount) of \(monitor.sources.count)"
    }

    private var landscapeSourceMenu: some View {
        Menu {
            ForEach(session.monitor.sources) { source in
                Button {
                    session.select(source)
                } label: {
                    Label("\(source.id + 1) · \(source.host) — \(source.status.description)",
                          systemImage: source.id == session.currentID ? "play.fill" : (source.isAlive ? "dot.radiowaves.left.and.right" : "circle"))
                }
            }
        } label: {
            Label("Source \((session.currentID ?? 0) + 1)", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.top, 56)
        .padding(.trailing, 16)
    }

    private var sourceList: some View {
        List {
            if let notice = session.notice {
                Section { Label(notice, systemImage: "info.circle").font(.footnote) }
            }
            Section {
                ForEach(session.monitor.sources) { source in
                    Button { session.select(source) } label: { sourceRow(source) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { session.select(source) } label: { Label("Play", systemImage: "play") }
                            Button { session.showInWebPlayer(source) } label: { Label("Open in web player", systemImage: "globe") }
                        }
                        .swipeActions {
                            Button { session.showInWebPlayer(source) } label: { Label("Web", systemImage: "globe") }.tint(.blue)
                        }
                }
            } header: {
                Text("Sources (\(session.aliveSources.count) live)")
            } footer: {
                Text("Sources are re-checked every \(settings.recheckInterval)s while you watch. Swipe a source to open it in the web player.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sourceRow(_ source: StreamSource) -> some View {
        HStack(spacing: 10) {
            StatusDot(status: source.status)
            VStack(alignment: .leading, spacing: 2) {
                Text("Source \(source.id + 1) · \(source.label)").font(.subheadline.weight(.medium))
                Text(source.host).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(source.status.description).font(.caption.weight(.semibold))
                    .foregroundStyle(source.isAlive ? .green : .secondary)
                if let checked = source.lastChecked {
                    Text(checked, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if source.id == session.currentID {
                Image(systemName: session.mode == .web ? "globe" : "play.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
