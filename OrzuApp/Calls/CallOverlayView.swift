import SwiftUI

/// Показывается поверх всего приложения, пока CallManager.state != .idle — см. RootView.
struct CallOverlayView: View {
    @ObservedObject private var callManager = CallManager.shared

    var body: some View {
        switch callManager.state {
        case .idle:
            Color.clear

        case .incomingRinging(_, let title, let isVideo):
            IncomingCallView(peerName: title, isVideo: isVideo)

        case .outgoingRinging(let title, let isVideo):
            ActiveCallView(peerName: title, isVideo: isVideo, statusText: "Звоним…", startedAt: nil)

        case .connecting(let title, let isVideo):
            ActiveCallView(peerName: title, isVideo: isVideo, statusText: "Соединение…", startedAt: nil)

        case .active(let title, let isVideo, let startedAt):
            ActiveCallView(peerName: title, isVideo: isVideo, statusText: nil, startedAt: startedAt)

        case .ended(let reason):
            EndedCallBanner(reason: reason)
        }
    }
}

private struct IncomingCallView: View {
    let peerName: String
    let isVideo: Bool
    @ObservedObject private var callManager = CallManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            CallAvatar(name: peerName)
                .padding(.bottom, 12)
            Text(peerName).font(.display(.title)).foregroundStyle(.white)
            Text(isVideo ? "Входящий видеозвонок · Бо Хам" : "Входящий звонок · Бо Хам").font(.app(.subheadline)).foregroundStyle(.white.opacity(0.75))
            Spacer()
            GlassGroup(spacing: 60) {
                HStack(spacing: 96) {
                    labeled("Отклонить") {
                        CallButton(systemImage: "phone.down.fill", tint: .red, title: "Отклонить", size: 76) { callManager.declineIncomingCall() }
                    }
                    labeled("Принять") {
                        CallButton(systemImage: isVideo ? "video.fill" : "phone.fill", tint: .green, title: "Принять", size: 76) { callManager.acceptIncomingCall() }
                    }
                }
            }
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CallBackground())
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder button: () -> Content) -> some View {
        VStack(spacing: 10) {
            button()
            Text(title).font(.app(.footnote)).foregroundStyle(.white)
        }
    }
}

private struct ActiveCallView: View {
    let peerName: String
    let isVideo: Bool
    let statusText: String?
    let startedAt: Date?
    @ObservedObject private var callManager = CallManager.shared

    var body: some View {
        ZStack {
            CallBackground()

            if isVideo {
                remoteVideos.ignoresSafeArea()
            }

            VStack {
                VStack(spacing: 6) {
                    if !isVideo {
                        CallAvatar(name: peerName).padding(.bottom, 8)
                    }
                    Text(peerName).font(.app(.title2, weight: .bold)).foregroundStyle(.white)
                    if let statusText {
                        Text(statusText).foregroundStyle(.white.opacity(0.8))
                    } else if let startedAt {
                        CallDurationText(startedAt: startedAt).foregroundStyle(.white.opacity(0.8))
                    }
                    // В групповом звонке показываем, кто уже на связи.
                    if callManager.participants.count > 1 {
                        Text(callManager.participants.map(\.name).joined(separator: ", "))
                            .font(.app(.footnote))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 8)
                .padding(.top, isVideo ? 24 : 80)

                Spacer()

                if isVideo && !callManager.isCameraOff {
                    HStack {
                        Spacer()
                        RTCVideoRenderView(track: callManager.localVideoTrack)
                            .frame(width: 110, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                            .shadow(radius: 10)
                            .padding()
                    }
                }

                controls
            }
        }
    }

    /// Один собеседник — на весь экран, несколько — сеткой в две колонки.
    @ViewBuilder
    private var remoteVideos: some View {
        let tracks = callManager.participants.compactMap(\.videoTrack)
        if tracks.count == 1, let track = tracks.first {
            RTCVideoRenderView(track: track)
        } else if tracks.count > 1 {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                ForEach(callManager.participants.filter { $0.videoTrack != nil }) { participant in
                    RTCVideoRenderView(track: participant.videoTrack)
                        .aspectRatio(3 / 4, contentMode: .fill)
                        .clipped()
                }
            }
        }
    }

    /// Кнопки в общем контейнере стекла: в iOS 26 они сливаются при смене состояния. Стекло на стекле HIG не рекомендует — общей подложки нет.
    private var controls: some View {
        GlassGroup(spacing: 24) {
            HStack(spacing: 24) {
                CallButton(
                    systemImage: callManager.isMuted ? "mic.slash.fill" : "mic.fill",
                    isOn: callManager.isMuted,
                    title: callManager.isMuted ? "Включить микрофон" : "Выключить микрофон"
                ) {
                    callManager.toggleMute()
                }
                if isVideo {
                    CallButton(
                        systemImage: callManager.isCameraOff ? "video.slash.fill" : "video.fill",
                        isOn: callManager.isCameraOff,
                        title: callManager.isCameraOff ? "Включить камеру" : "Выключить камеру"
                    ) {
                        callManager.toggleCamera()
                    }
                } else {
                    CallButton(
                        systemImage: callManager.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                        isOn: callManager.isSpeakerOn,
                        title: callManager.isSpeakerOn ? "Выключить динамик" : "Включить динамик"
                    ) {
                        callManager.toggleSpeaker()
                    }
                }
                CallButton(systemImage: "phone.down.fill", tint: .red, title: "Завершить") { callManager.endCall() }
            }
        }
        .padding(.bottom, 48)
    }
}

private struct EndedCallBanner: View {
    let reason: String

    var body: some View {
        Text(reasonText)
            .font(.app(.headline))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .glassSurface()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CallBackground())
    }

    private var reasonText: String {
        switch reason {
        case "declined": return "Собеседник отклонил звонок"
        case "busy": return "Собеседник сейчас занят"
        case "unavailable": return "Собеседник недоступен"
        case "timeout": return "Никто не ответил"
        case "connection-lost": return "Соединение потеряно"
        case "full": return "В звонке уже максимум участников"
        case "gone": return "Звонок уже завершён"
        default: return "Звонок завершён"
        }
    }
}

/// Круглая стеклянная кнопка звонка. `isOn` — режим включён (микрофон выключен и т.п.): светлая заливка, тёмная иконка.
private struct CallButton: View {
    let systemImage: String
    var tint: Color?
    var isOn = false
    let title: String
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: size, height: size)
                .glassSurface(in: Circle(), tint: isOn ? .white : tint, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Затемнённое «северное сияние»: стеклу нужен фон, а белый текст должен читаться.
private struct CallBackground: View {
    var body: some View {
        ZStack {
            AuroraBackground().environment(\.colorScheme, .dark)
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

private struct CallAvatar: View {
    let name: String

    var body: some View {
        // Золотой ободок и мягкие гранатовые круги — как у значка «проверен» и кнопки лайка.
        AvatarView(avatarUrl: nil, name: name, size: 124)
            .padding(6)
            .overlay(Circle().strokeBorder(Color(rgb: 0xF0C27B).opacity(0.7), lineWidth: 2))
            .background(Circle().fill(Color(rgb: 0xE2455F).opacity(0.12)).padding(-16))
            .background(Circle().fill(Color(rgb: 0xE2455F).opacity(0.06)).padding(-34))
    }
}

private struct CallDurationText: View {
    let startedAt: Date
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted).monospacedDigit().onReceive(timer) { now = $0 }
    }

    private var formatted: String {
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
