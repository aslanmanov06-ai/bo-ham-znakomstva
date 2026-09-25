import SwiftUI
import UIKit

/// Подтверждение анкеты селфи: человек повторяет случайный жест, модератор сверяет селфи с фото анкеты и жестом.
/// Без подтверждения анкету не видят в ленте, а лайки и первые сообщения недоступны.
struct SelfieVerificationView: View {
    @ObservedObject var dating: DatingViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var isSending = false
    @State private var isChangingGesture = false
    @State private var errorMessage: String?

    private let maxSelfieDimension: CGFloat = 1600

    var body: some View {
        content
            .navigationTitle("Проверка анкеты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Просьбу модератора можно отложить — значок пока остаётся.
                    Button(isReverification ? "Позже" : "Закрыть") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                SelfieCamera(gesture: gesture) { submit($0) }
                    .ignoresSafeArea()
            }
            .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
                Button("Ок") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isReverification {
            reverificationContent
        } else if canSubmit {
            gestureContent
        } else {
            statusContent
        }
    }

    // MARK: - Первая проверка (макет «Селфи с жестом»)

    private var gestureContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Повторите жест на селфи")
                    .font(.display(size: 21))
                    .multilineTextAlignment(.center)
                rejectedLabel
                gestureCard
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Покажите жест рядом с лицом")
                    step(2, "Модератор сверит селфи с фото анкеты")
                    step(3, "Рядом с именем появится значок «проверен»")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(cornerRadius: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { cameraButton }
        .background(AppBackground())
    }

    // MARK: - Модератор попросил переснять (макет «Модератор просит селфи»)

    private var reverificationContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    HaloIcon(systemImage: "person.crop.rectangle", tint: .champagne, fill: .champagneSoft)
                        .padding(.top, 10)
                    Text("Модератор просит новое селфи")
                        .font(.display(size: 21))
                        .multilineTextAlignment(.center)
                    Text("Значок «проверен» и анкета остаются — лента, лайки и переписки работают как обычно.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let reason = dating.verification?.reverificationReason {
                    ReasonCard(reason: reason)
                }
                rejectedLabel
                gestureCard
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Покажите жест рядом с лицом")
                    step(2, "Модератор сверит его с фото анкеты")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(cornerRadius: 20)
                Label("Селфи видит только модератор, в анкете его нет", systemImage: "lock")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) { cameraButton }
        .background(AppBackground())
    }

    // MARK: - Селфи на проверке или анкета уже подтверждена

    private var statusContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                statusIcon
                    .padding(.top, 12)
                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.display(.title2))
                        .multilineTextAlignment(.center)
                    Text(statusDescription)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .background(DatingBackdrop())
    }

    /// Проверено — золотая печать, на проверке — часы с расходящимися кругами.
    private var statusIcon: some View {
        ZStack {
            if latest?.status == .pending, dating.verification?.verified != true {
                PulseRings(color: .champagne)
                    .frame(width: 96, height: 96)
            }
            Image(systemName: dating.verification?.verified == true ? "checkmark.seal.fill" : "clock.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.champagne, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .symbolEffect(.bounce, value: dating.verification?.verified)
        }
        .frame(height: 150)
    }

    private var statusTitle: String {
        dating.verification?.verified == true ? "Анкета подтверждена" : "Селфи на проверке"
    }

    private var statusDescription: String {
        if dating.verification?.verified == true {
            return "Рядом с вашим именем стоит значок «проверен» — такие анкеты вызывают больше доверия."
        }
        return "Проверим в течение 24 часов: модератор сверит селфи с фото анкеты и жестом."
    }

    // MARK: - Общие части

    /// Жест крупно и «Другой жест», если этот неудобен (сервер разрешает сменить три раза в день).
    @ViewBuilder
    private var gestureCard: some View {
        if let gesture {
            VStack(spacing: 12) {
                Text(gesture.emoji)
                    .font(.system(size: 64))
                    .frame(width: 120, height: 120)
                    .background(Color.champagneSoft, in: Circle())
                    .background(Circle().fill(Color.champagne.opacity(0.07)).padding(-12))
                    .accessibilityHidden(true)
                Text(gesture.title)
                    .font(.app(size: 18, weight: .semibold))
                    .padding(.top, 6)
                Button(action: changeGesture) {
                    HStack(spacing: 6) {
                        if isChangingGesture {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Другой жест")
                    }
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
                .disabled(isChangingGesture || isSending)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .appCard(cornerRadius: 20, padding: nil)
        }
    }

    @ViewBuilder
    private var rejectedLabel: some View {
        if let reason = rejectReason {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.app(.footnote, weight: .medium))
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.app(size: 13, weight: .bold))
                .foregroundStyle(number == 1 ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background {
                    if number == 1 {
                        Circle().fill(.brandFill)
                    } else {
                        Circle().fill(Color.appElevated)
                    }
                }
            Text(text).font(.app(.subheadline))
        }
    }

    /// Селфи только с камеры, прямо сейчас: выбрать фото из галереи нельзя.
    private var cameraButton: some View {
        Button(action: openCamera) {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "camera.fill")
                }
                Text(isSending ? "Отправляем…" : "Сделать селфи")
            }
            .font(.app(.headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DatingStyle.brandGradient, in: Capsule())
            .shadow(color: DatingStyle.rose.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSending || isChangingGesture)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var gesture: SelfieGesture? {
        dating.verification?.gesture
    }

    private var latest: SelfieCheck? {
        dating.verification?.latest
    }

    private var canSubmit: Bool {
        (dating.verification?.verified != true || dating.selfieRequested) && latest?.status != .pending
    }

    /// Значок есть, но модератор попросил новое селфи — и оно ещё не отправлено.
    private var isReverification: Bool {
        dating.verification?.verified == true && dating.selfieRequested
    }

    private var rejectReason: String? {
        guard latest?.status == .rejected else { return nil }
        return latest?.rejectReason ?? "Селфи отклонено — попробуйте ещё раз"
    }

    private func changeGesture() {
        isChangingGesture = true
        Task {
            defer { isChangingGesture = false }
            do {
                try await dating.rerollSelfieGesture()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openCamera() {
        guard SelfieCamera.isAvailable else {
            errorMessage = "На этом устройстве нет фронтальной камеры — пройдите проверку с iPhone"
            return
        }
        Task {
            do {
                try await SelfieCamera.ensureAccess()
                showCamera = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit(_ image: UIImage) {
        guard let jpeg = image.downscaled(maxDimension: maxSelfieDimension).jpegData(compressionQuality: 0.85) else {
            errorMessage = "Не удалось сохранить снимок — попробуйте ещё раз"
            return
        }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let attachment = try await APIClient.shared.uploadAttachment(data: jpeg, fileName: "selfie.jpg", mimeType: "image/jpeg")
                _ = try await APIClient.shared.submitSelfie(attachmentId: attachment.id)
                await dating.refreshVerification()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
