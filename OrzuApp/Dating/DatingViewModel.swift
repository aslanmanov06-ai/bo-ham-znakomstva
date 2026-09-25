import Combine
import Foundation

/// Состояние вкладки «Знакомства»: правила сообщества, справочник и своя анкета.
/// Лента, пары и встречи живут в своих моделях — здесь только то, без чего вкладку вообще не открыть.
@MainActor
final class DatingViewModel: ObservableObject {
    enum Stage: Equatable {
        case loading
        /// Пока не приняты действующие правила, сервер закрывает все запросы знакомств.
        case rules(CommunityRules)
        case noProfile
        case ready

        static func == (lhs: Stage, rhs: Stage) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.noProfile, .noProfile), (.ready, .ready): return true
            case (.rules(let left), .rules(let right)): return left.version == right.version
            default: return false
            }
        }
    }

    @Published private(set) var stage: Stage = .loading
    @Published private(set) var catalog: DatingCatalog?
    @Published private(set) var profile: DatingProfileMine?
    @Published private(set) var completeness: ProfileCompleteness?
    @Published private(set) var verification: VerificationStatus?
    /// Кого ищет человек (код пола). По нему подбирается лента и заполняется сетка анкет.
    @Published private(set) var lookingFor: String?
    @Published var errorMessage: String?
    /// Растёт после смены «Кого ищу» или расстояния в «Моём профиле» — лента и сетка анкет перезагружаются.
    @Published private(set) var searchSettingsRevision = 0

    /// Загрузку запускают .task нескольких экранов (корень, вкладки, «Мой профиль») — все ждут одну и ту же.
    /// Задача принадлежит модели, а не экрану: SwiftUI отменяет .task, когда пересоздаёт экран, и запрос
    /// обрывался с URLError.cancelled — вкладка показывала «Ошибка: Cancelled» и оставалась без анкеты.
    private var loadTask: Task<Void, Never>?
    /// Координаты обновляем раз за запуск приложения: чаще расстояние «в километрах» не меняется.
    private var locationRefreshed = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Модератор проверил селфи, фото или видео — статусы и значок «проверен» должны обновиться сразу.
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard case .datingModerated = event else { return }
                Task { await self?.reloadProfile() }
            }
            .store(in: &cancellables)
    }

    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        do {
            // Справочник нужен всем экранам знакомств: без подписей к кодам показывать нечего.
            if catalog == nil {
                catalog = try await APIClient.shared.fetchDatingCatalog()
            }
            apply(try await APIClient.shared.fetchMyDatingProfile())
            verification = try await APIClient.shared.fetchVerificationStatus()
            // Отдельной задачей: ждать спутники, чтобы открыть вкладку, незачем.
            Task { await refreshLocationIfNeeded() }
        } catch let error as APIError where error.code == ServerErrorCode.termsNotAccepted {
            await loadRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptRules(version: String) async {
        do {
            try await APIClient.shared.acceptCommunityRules(version: version)
            stage = .loading
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ответ любого запроса, который возвращает анкету целиком (правка, фото, видео, геопозиция).
    func apply(_ response: MyDatingProfile) {
        profile = response.profile
        completeness = response.completeness
        stage = response.profile == nil ? .noProfile : .ready
    }

    /// Перечитать анкету и статус подтверждения, не трогая шаг вкладки (правила или отсутствие анкеты).
    func reloadProfile() async {
        guard let response = try? await APIClient.shared.fetchMyDatingProfile() else { return }
        apply(response)
        await refreshVerification()
    }

    func refreshVerification() async {
        verification = try? await APIClient.shared.fetchVerificationStatus()
    }

    /// Ошибку (лимит смен) показывает экран проверки.
    func rerollSelfieGesture() async throws {
        verification = try await APIClient.shared.rerollSelfieGesture()
    }

    /// Нужно только настройкам, поэтому грузится оттуда: сбой не должен закрывать вкладки знакомств.
    /// Без анкеты сервер его не отдаёт.
    func loadLookingFor() async throws {
        lookingFor = try await APIClient.shared.fetchSearchSettings().lookingFor
    }

    /// Ошибку показывает экран настроек, откуда меняют «Кого ищу».
    func setLookingFor(_ gender: String) async throws {
        let saved = try await APIClient.shared.updateSearchSettings(DatingSearchSettings(lookingFor: gender))
        lookingFor = saved.lookingFor
        searchSettingsRevision += 1
    }

    /// Скрытая анкета пропадает из ленты и сетки анкет; чаты и пары остаются. Ошибку показывает экран с переключателем.
    func setHidden(_ hidden: Bool) async throws {
        var update = DatingProfileUpdate()
        update.hidden = hidden
        apply(try await APIClient.shared.updateMyDatingProfile(update))
    }

    /// Включение спрашивает доступ к геопозиции и отправляет координаты, выключение стирает их на сервере.
    /// Ошибку показывает экран, где переключатель.
    func setShowsDistance(_ enabled: Bool) async throws {
        if enabled {
            try await sendCurrentLocation()
        } else {
            apply(try await APIClient.shared.clearDatingLocation())
        }
        // Карточки ленты и сетки пришли со старым расстоянием (или без него) — пусть перезагрузятся.
        searchSettingsRevision += 1
    }

    /// Сетка анкет сама предлагает включить расстояние, пока человек не ответил на системный вопрос.
    /// iOS задаёт его один раз; отказ — выбор человека, а не ошибка: расстояние просто не показывается.
    func askForDistanceIfUndecided() async throws {
        guard LocationProvider.shared.isUndecided, profile?.hasLocation == false else { return }
        do {
            try await setShowsDistance(true)
        } catch LocationProvider.LocationError.denied {
            return
        }
    }

    /// Человек переехал или уехал в другой город — расстояния должны считаться от того места, где он сейчас.
    /// Только если расстояние включено и доступ уже дан: системный вопрос посреди открытия вкладки неуместен.
    private func refreshLocationIfNeeded() async {
        guard !locationRefreshed, profile?.hasLocation == true, LocationProvider.shared.isAuthorized else { return }
        locationRefreshed = true
        do {
            try await sendCurrentLocation()
        } catch {
            // Фоновое обновление: на сервере остаются прежние координаты, попробуем при следующей загрузке.
            locationRefreshed = false
        }
    }

    private func sendCurrentLocation() async throws {
        let location = try await LocationProvider.shared.current()
        apply(try await APIClient.shared.setDatingLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
    }

    /// Анкета — профиль человека и обязательна: пока нет анкеты с хотя бы одним неотклонённым фото, вместо вкладок —
    /// её заполнение (сервер без неё не даёт искать людей, писать незнакомым и знакомиться). Пока анкета не загрузилась
    /// (в том числе без сети), не запираем: показываем вкладки с сохранёнными данными.
    var needsOnboarding: Bool {
        switch stage {
        case .loading: return false
        case .rules, .noProfile: return true
        case .ready: return profile?.photos.allSatisfy { $0.status == .rejected } ?? false
        }
    }

    /// Значок «проверен» снимается после полной замены фото — тогда нужно новое селфи.
    var needsSelfie: Bool {
        guard let profile else { return false }
        return !profile.shared.verified
    }

    var selfiePending: Bool {
        verification?.latest?.status == .pending
    }

    /// Модератор просит переснять селфи, а новое ещё не отправлено: значок есть, но нужна проверка.
    var selfieRequested: Bool {
        verification?.reverificationRequested == true && !selfiePending
    }

    private func loadRules() async {
        do {
            stage = .rules(try await APIClient.shared.fetchCommunityRules())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
