import PhotosUI
import SwiftUI
import UIKit

/// Подтверждение анкеты селфи: модератор сравнивает свежее селфи с фото анкеты.
/// Без подтверждения анкету не видят в ленте, а лайки и первые сообщения недоступны.
struct SelfieVerificationView: View {
    @ObservedObject var dating: DatingViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var isSending = false
    @State private var errorMessage: String?

    private let maxSelfieDimension: CGFloat = 1600

    var body: some View {
        if isReverification {
            reverificationBody
        } else {
            firstCheckBody
        }
    }

    private var firstCheckBody: some View {
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

                if let reason = rejectReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if canSubmit {
                    steps
                    tips
                    selfiePicker
                }
            }
            .padding(24)
        }
        .background(DatingBackdrop())
        .navigationTitle("Подтверждение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .onChange(of: item) { _, selected in
            guard let selected else { return }
            submit(selected)
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Модератор попросил переснять селфи (макет «Модератор просит селфи»): значок остаётся, отказываться не страшно.
    private var reverificationBody: some View {
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
                if let rejected = rejectReason {
                    Label(rejected, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Сделайте селфи с жестом с картинки")
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
        .safeAreaInset(edge: .bottom) {
            selfiePicker
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(AppBackground())
        .navigationTitle("Проверка анкеты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Позже") { dismiss() }
            }
        }
        .onChange(of: item) { _, selected in
            guard let selected else { return }
            submit(selected)
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Выбор селфи из фото телефона: камера в приложении пока не встроена.
    private var selfiePicker: some View {
        PhotosPicker(selection: $item, matching: .images) {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "camera.fill")
                }
                Text(isSending ? "Отправляем…" : "Выбрать селфи")
            }
            .font(.app(.headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DatingStyle.brandGradient, in: Capsule())
            .shadow(color: DatingStyle.rose.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSending)
    }

    /// Значок есть, но модератор попросил новое селфи — и оно ещё не отправлено.
    private var isReverification: Bool {
        dating.verification?.verified == true && dating.selfieRequested
    }

    /// Проверено — золотая печать, на проверке — часы с расходящимися кругами, иначе — камера.
    private var statusIcon: some View {
        ZStack {
            if latest?.status == .pending, dating.verification?.verified != true {
                PulseRings(color: .champagne)
                    .frame(width: 96, height: 96)
            }
            Image(systemName: statusSymbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.champagne, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .symbolEffect(.bounce, value: dating.verification?.verified)
        }
        .frame(height: 150)
    }

    private var statusSymbol: String {
        if dating.verification?.verified == true { return "checkmark.seal.fill" }
        return latest?.status == .pending ? "clock.fill" : "person.crop.square.badge.camera"
    }

    /// Что будет дальше — тремя шагами, чтобы проверка не казалась чёрным ящиком.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "Сделайте свежее селфи")
            step(2, "Модератор сравнит его с фото анкеты")
            step(3, "Рядом с именем появится значок «проверен»")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: DatingStyle.tileCornerRadius)
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

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            tip("sun.max.fill", "Хороший свет, лицо целиком")
            tip("eyeglasses", "Без очков и головного убора")
            tip("eye.slash.fill", "Селфи видит только модератор")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
    }

    private func tip(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.app(.subheadline))
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(DatingStyle.rose)
        }
    }

    private var latest: SelfieCheck? {
        dating.verification?.latest
    }

    private var canSubmit: Bool {
        (dating.verification?.verified != true || dating.selfieRequested) && latest?.status != .pending
    }

    private var statusTitle: String {
        if dating.verification?.verified == true { return "Анкета подтверждена" }
        if latest?.status == .pending { return "Селфи на проверке" }
        return "Получите золотой значок"
    }

    private var statusDescription: String {
        if dating.verification?.verified == true {
            return "Рядом с вашим именем стоит значок «проверен» — такие анкеты вызывают больше доверия."
        }
        if latest?.status == .pending {
            return "Модератор сравнит селфи с фото анкеты. Обычно это занимает несколько часов."
        }
        return "Модератор сверит селфи с фото анкеты, и рядом с вашим именем появится значок «проверен»."
    }

    private var rejectReason: String? {
        guard latest?.status == .rejected else { return nil }
        return latest?.rejectReason ?? "Селфи отклонено — попробуйте ещё раз"
    }

    private func submit(_ selected: PhotosPickerItem) {
        isSending = true
        Task {
            defer {
                isSending = false
                item = nil
            }
            guard
                let data = try? await selected.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let jpeg = image.downscaled(maxDimension: maxSelfieDimension).jpegData(compressionQuality: 0.85)
            else {
                errorMessage = "Не удалось прочитать фото"
                return
            }
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
