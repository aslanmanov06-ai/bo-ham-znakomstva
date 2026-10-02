import SwiftUI
import WebRTC

/// Видеоразговор в рулетке (макеты «Видеоразговор» и «Видео — первые секунды размыты»).
struct RouletteVideoView: View {
    @ObservedObject var roulette: RouletteViewModel
    @ObservedObject var engine: RouletteVideoEngine
    let session: RouletteViewModel.Session
    let places: RoulettePlaces

    @State private var isRevealed = false
    @State private var countdown = Int(RouletteViewModel.videoRevealDelay)

    var body: some View {
        ZStack {
            remote
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            if !isRevealed { revealNotice }
            if engine.isSensitiveHidden {
                sensitiveCover
            } else {
                VStack(spacing: 0) {
                    topBar
                    if let notice = roulette.notice {
                        Text(notice)
                            .font(.app(.footnote, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.top, 10)
                            .transition(.opacity)
                    }
                    Spacer()
                    tools
                        .padding(.bottom, 22)
                    mainButtons
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: engine.isSensitiveHidden)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .task(id: session.id) { await reveal() }
    }

    // MARK: - Откровенное видео

    /// Макет «Откровенное видео скрыто»: iPhone скрыл видео на устройстве, человек решает, что дальше.
    private var sensitiveCover: some View {
        VStack(spacing: 0) {
            HStack {
                Text(places.peerLine(session.peer))
                    .font(.app(.subheadline, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.14), in: Capsule())
                Spacer()
            }
            .padding(.top, 14)
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 32, weight: .medium))
                    .frame(width: 76, height: 76)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                Text("Видео может быть откровенным")
                    .font(.display(size: 21))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                Text("iPhone скрыл его прямо на устройстве — мы ничего не видим и не сохраняем. Вы решаете, что дальше.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    roulette.next()
                } label: {
                    Label("Следующий собеседник", systemImage: "shuffle")
                }
                .buttonStyle(.appPrimary)
                Button {
                    roulette.beginReport()
                } label: {
                    Label("Пожаловаться и завершить", systemImage: "flag")
                        .font(.app(.callout, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                Button("Всё равно показать") { engine.showSensitiveVideo() }
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(10)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .background(Color.black.opacity(0.55))
    }

    // MARK: - Видео

    private var remote: some View {
        ZStack {
            RadialGradient(colors: [Color(rgb: 0x4A3540), Color(rgb: 0x241A21)], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 420)
            if engine.remoteTrack == nil {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Соединяемся…")
                        .font(.app(.subheadline))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                RTCVideoRenderView(track: engine.remoteTrack)
            }
        }
        .blur(radius: engine.isSensitiveHidden ? 40 : isRevealed ? 0 : 24)
        .scaleEffect(isRevealed ? 1 : 1.1)
        .clipped()
        .ignoresSafeArea()
        .accessibilityLabel(Text(places.peerLine(session.peer)))
    }

    /// Первые секунды видео размыто: если на той стороне что-то неприятное, человек успеет нажать «Далее».
    private func reveal() async {
        isRevealed = false
        countdown = Int(RouletteViewModel.videoRevealDelay)
        while countdown > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            countdown -= 1
        }
        withAnimation(.easeOut(duration: 0.6)) { isRevealed = true }
    }

    private var revealNotice: some View {
        VStack(spacing: 14) {
            Text("\(max(countdown, 1))")
                .font(.display(size: 28))
                .monospacedDigit()
                .frame(width: 76, height: 76)
                .overlay {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(countdown) / CGFloat(RouletteViewModel.videoRevealDelay))
                        .stroke(Color.champagne, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: countdown)
                }
            Text(session.peer.isFemale ? String(localized: "Собеседница нашлась") : String(localized: "Собеседник нашёлся"))
                .font(.display(size: 19))
            Text("Видео проясняется через пару секунд — можно сразу нажать «Далее»")
                .font(.app(.subheadline))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    // MARK: - Панели

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    if session.peer.verified { VerifiedBadge().font(.system(size: 16)) }
                    Text(session.peer.title)
                        .font(.app(.callout, weight: .semibold))
                    Text("· \(places.city(session.peer.cityCode))")
                        .font(.app(.callout))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Circle().fill(engine.isConnected ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text(Duration.seconds(context.date.timeIntervalSince(session.startedAt)).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                    }
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.leading, 2)
                }
            }
            .foregroundStyle(.white)
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                glassCircle(systemImage: "flag", title: String(localized: "Пожаловаться"), size: 44) { roulette.beginReport() }
                RTCVideoRenderView(track: engine.isCameraOff ? nil : engine.localTrack)
                    .background(Color(rgb: 0x2E2329))
                    .frame(width: 104, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
                    .accessibilityLabel("Ваша камера")
            }
        }
        .padding(.top, 8)
    }

    private var tools: some View {
        HStack(spacing: 18) {
            glassCircle(systemImage: engine.isMuted ? "mic.slash.fill" : "mic.fill", title: engine.isMuted ? String(localized: "Включить микрофон") : String(localized: "Выключить микрофон"), size: 48, action: engine.toggleMute)
            glassCircle(systemImage: engine.isCameraOff ? "video.slash.fill" : "video.fill", title: engine.isCameraOff ? String(localized: "Включить камеру") : String(localized: "Выключить камеру"), size: 48, action: engine.toggleCamera)
            glassCircle(systemImage: "arrow.triangle.2.circlepath.camera", title: String(localized: "Сменить камеру"), size: 48, action: engine.flipCamera)
        }
    }

    private var mainButtons: some View {
        HStack(alignment: .top, spacing: 30) {
            labeled(String(localized: "Стоп")) {
                glassCircle(systemImage: "xmark", title: String(localized: "Стоп"), size: 60, action: roulette.stop)
            }
            labeled(roulette.liked ? String(localized: "Ждём ответа") : String(localized: "Нравится")) {
                Button(action: roulette.like) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(roulette.liked ? Color.brand : .white)
                        .frame(width: 76, height: 76)
                        .background {
                            if roulette.liked {
                                Circle().fill(.white)
                            } else {
                                Circle().fill(.brandFill)
                            }
                        }
                        .shadow(color: Color.brand.opacity(0.45), radius: 13, y: 10)
                        .symbolEffect(.bounce, value: roulette.liked)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(roulette.liked)
                .accessibilityLabel("Нравится")
                .accessibilityAddTraits(roulette.liked ? .isSelected : [])
            }
            labeled(String(localized: "Далее")) {
                Button(action: roulette.next) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(rgb: 0x120E12))
                        .frame(width: 60, height: 60)
                        .background(Color.champagne, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Далее")
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 7) {
            content()
            Text(title)
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func glassCircle(systemImage: String, title: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.5), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}
