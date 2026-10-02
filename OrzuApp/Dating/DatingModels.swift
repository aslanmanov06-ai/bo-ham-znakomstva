import Foundation

// Коды справочника (пол, цель знакомства, образование, интересы, города) приходят с сервера строками,
// а подписи к ним — в каталоге GET /dating/catalog. Поэтому в моделях хранятся коды, а тексты берутся
// из каталога: их можно менять и переводить на сервере, не обновляя приложение.

struct CatalogItem: Codable, Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}

struct CatalogCountry: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let cities: [CatalogItem]

    var id: String { code }
}

struct JourneyStageInfo: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let description: String
    /// Вопросы для разговора на этой ступени — их можно отправить в чат пары.
    let questions: [String]

    var id: String { code }
}

struct JourneyCatalog: Codable, Hashable {
    let stages: [JourneyStageInfo]
    let checklist: [CatalogItem]
}

/// Вопрос-подсказка для анкеты («Идеальное воскресенье — это…»): человек выбирает до трёх и отвечает своими словами.
struct CatalogPrompt: Codable, Identifiable, Hashable {
    let code: String
    let text: String

    var id: String { code }
}

struct DatingCatalog: Codable, Hashable {
    let journey: JourneyCatalog
    let countries: [CatalogCountry]
    let interests: [CatalogItem]
    let hobbies: [CatalogItem]
    let cuisines: [CatalogItem]
    let genders: [CatalogItem]
    let relationshipGoals: [CatalogItem]
    let maritalStatuses: [CatalogItem]
    let children: [CatalogItem]
    let wantsChildren: [CatalogItem]
    let education: [CatalogItem]
    let habitFrequencies: [CatalogItem]
    /// nil — сервер ещё не умеет вопросы в анкете: раздел не показываем и поле prompts не отправляем.
    var prompts: [CatalogPrompt]? = nil

    func prompt(_ code: String) -> CatalogPrompt? {
        prompts?.first { $0.code == code }
    }

    func cities(in countryCode: String) -> [CatalogItem] {
        countries.first { $0.code == countryCode }?.cities ?? []
    }

    func cityName(countryCode: String, cityCode: String) -> String {
        cities(in: countryCode).first { $0.code == cityCode }?.name ?? cityCode
    }

    func stage(_ code: String) -> JourneyStageInfo? {
        journey.stages.first { $0.code == code }
    }

    /// Подписи для набора кодов в том порядке, в каком они идут в справочнике.
    func names(of codes: [String], in items: [CatalogItem]) -> [String] {
        items.filter { codes.contains($0.code) }.map(\.name)
    }
}

extension Array where Element == CatalogItem {
    func name(of code: String?) -> String? {
        guard let code else { return nil }
        return first { $0.code == code }?.name ?? code
    }
}

enum ModerationStatus: String, Codable, Hashable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

/// Ответ на вопрос анкеты. status и rejectReason приходят только в своей анкете: ответы проверяет модератор.
struct ProfilePromptAnswer: Codable, Hashable {
    var code: String
    var answer: String
    var status: ModerationStatus? = nil
    var rejectReason: String? = nil

    private enum CodingKeys: String, CodingKey {
        case code, answer, status, rejectReason
    }

    init(code: String, answer: String) {
        self.code = code
        self.answer = answer
    }

    /// На сервер уходят только вопрос и ответ — статус ставит модератор.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(answer, forKey: .answer)
    }
}

/// Когда человек был в приложении — корзинами, без точного времени (его сервер не раскрывает).
enum DatingActivity: String, Hashable {
    case online
    case today
    case week

    var title: String {
        switch self {
        case .online: return String(localized: "В сети")
        case .today: return String(localized: "Был(а) сегодня")
        case .week: return String(localized: "Был(а) на этой неделе")
        }
    }
}

/// Анкета глазами другого пользователя: только одобренные фото и видео.
struct DatingProfilePublic: Codable, Identifiable, Hashable {
    let userId: String
    /// nil — ответ старого сервера или анкета из кеша до обновления.
    var username: String? = nil
    let displayName: String
    let age: Int
    let gender: String
    let countryCode: String
    let cityCode: String
    let heightCm: Int?
    let bio: String
    let interests: [String]
    let education: String?
    let profession: String?
    let relationshipGoal: String?
    let maritalStatus: String?
    let children: String?
    let wantsChildren: String?
    let smoking: String?
    let alcohol: String?
    let sport: String?
    let cuisines: [String]
    let hobbies: [String]
    let photoIds: [String]
    let videoId: String?
    /// Селфи подтверждено модератором и фото с тех пор не меняли целиком.
    let verified: Bool
    /// Сколько километров до этого человека. nil — у кого-то из двоих выключена геопозиция или это своя анкета.
    let distanceKm: Int?
    /// Ответы на вопросы анкеты (до трёх). nil — старый сервер.
    var prompts: [ProfilePromptAnswer]? = nil
    /// Голосовое приветствие (одобренное модератором) и его длительность.
    var voiceId: String? = nil
    var voiceDurationSec: Int? = nil
    /// online, today, week. Строкой, а не enum: новое значение с сервера не должно ломать разбор всей анкеты.
    var activity: String? = nil
    /// Анкета «Кого ищу» этого человека. nil — он её не заполнял или сервер старый.
    var searchCriteria: SearchCriteria? = nil
    /// Подхожу ли я под его «Кого ищу». nil — не заполнена, своя анкета или сервер старый.
    var fitsCriteria: Bool? = nil

    var id: String { userId }

    /// Собеседник для мессенджера. Аватар подтянется из списка чатов — в анкете его пути нет.
    var messengerUser: User {
        User(id: userId, username: username ?? "", displayName: displayName, avatarUrl: nil)
    }

    /// nil — человек скрыл активность, давно не заходил, сервер её не знает или это своя анкета.
    var activityStatus: DatingActivity? {
        activity.flatMap(DatingActivity.init(rawValue:))
    }

    /// Голосовое приветствие как вложение — его играет тот же плеер, что и голосовые в чате.
    var voiceAttachment: Attachment? {
        voiceId.map { Attachment(id: $0, kind: .voice, mimeType: "audio/mp4", fileName: "voice.m4a", size: 0, durationSec: voiceDurationSec) }
    }

    /// «12 км» для подписи под именем; сервер уже округлил до километра.
    var distanceText: String? {
        distanceKm.map { String(localized: "\($0) км") }
    }

    /// «Душанбе · 3 км» — подпись под именем в карточках анкет.
    func locationLine(catalog: DatingCatalog?) -> String {
        let city = catalog?.cityName(countryCode: countryCode, cityCode: cityCode) ?? cityCode
        return [city, distanceText].compactMap { $0 }.joined(separator: " · ")
    }
}

struct DatingPhoto: Codable, Identifiable, Hashable {
    let attachmentId: String
    let status: ModerationStatus
    let rejectReason: String?
    /// Только у видео и голосового: PROCESSING — сервер ещё перекодирует файл, FAILED — не смог.
    var mediaStatus: String? = nil

    var isProcessing: Bool { mediaStatus == "PROCESSING" }
    var processingFailed: Bool { mediaStatus == "FAILED" }

    var id: String { attachmentId }
}

/// Почему анкету не видят другие (VisibilityIssue на сервере).
enum VisibilityIssue: String, Codable, Hashable {
    case hidden = "HIDDEN"
    case deactivated = "DEACTIVATED"
    case notVerified = "NOT_VERIFIED"
    case noApprovedPhotos = "NO_APPROVED_PHOTOS"
    case restricted = "RESTRICTED"
    case inCouple = "IN_COUPLE"

    var explanation: String {
        switch self {
        case .hidden: return String(localized: "Анкета скрыта вами — включите её в «Настройках»")
        case .deactivated: return String(localized: "Аккаунт деактивирован")
        case .notVerified: return String(localized: "Нужно подтвердить анкету селфи")
        case .noApprovedPhotos: return String(localized: "Нет ни одного фото, одобренного модератором")
        case .restricted: return String(localized: "Анкета временно скрыта модератором")
        case .inCouple: return String(localized: "Вы отметили, что нашли пару")
        }
    }
}

/// Своя анкета: общие поля плюс фото со статусами модерации и причины, почему её не видят.
struct DatingProfileMine: Decodable, Hashable {
    let shared: DatingProfilePublic
    let photos: [DatingPhoto]
    let video: DatingPhoto?
    let inCouple: Bool
    /// ГГГГ-ММ-ДД — так же отправляется обратно.
    let birthDate: String
    let hidden: Bool
    let visibleToOthers: Bool
    let visibilityIssues: [VisibilityIssue]
    /// Фото заменили целиком: анкета видна, но значок «проверен» вернётся только после нового селфи.
    let needsReverification: Bool
    let hasLocation: Bool
    /// Голосовое приветствие со статусом модерации.
    let voice: DatingPhoto?
    /// Сервер прислал ключ voice (хотя бы null) — значит, умеет голосовое приветствие и строку можно показать.
    let supportsVoice: Bool
    /// С какого момента дату рождения снова можно менять (раз в 90 дней). nil — можно уже сейчас.
    let birthDateEditableFrom: Date?

    private enum CodingKeys: String, CodingKey {
        case photos, video, inCouple, birthDate, hidden, visibleToOthers, visibilityIssues, needsReverification, hasLocation
        case voice, birthDateEditableFrom
    }

    init(from decoder: Decoder) throws {
        // Сервер отдаёт одну плоскую анкету: общие поля разбирает DatingProfilePublic, остальные — здесь.
        shared = try DatingProfilePublic(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photos = try container.decode([DatingPhoto].self, forKey: .photos)
        video = try container.decodeIfPresent(DatingPhoto.self, forKey: .video)
        inCouple = try container.decode(Bool.self, forKey: .inCouple)
        birthDate = try container.decode(String.self, forKey: .birthDate)
        hidden = try container.decode(Bool.self, forKey: .hidden)
        visibleToOthers = try container.decode(Bool.self, forKey: .visibleToOthers)
        visibilityIssues = try container.decode([VisibilityIssue].self, forKey: .visibilityIssues)
        needsReverification = try container.decode(Bool.self, forKey: .needsReverification)
        hasLocation = try container.decode(Bool.self, forKey: .hasLocation)
        voice = try container.decodeIfPresent(DatingPhoto.self, forKey: .voice)
        supportsVoice = container.contains(.voice)
        birthDateEditableFrom = try container.decodeIfPresent(Date.self, forKey: .birthDateEditableFrom)
    }
}

/// Насколько заполнена анкета: missing — ключи незаполненных пунктов.
struct ProfileCompleteness: Decodable, Hashable {
    let percent: Int
    let missing: [String]
}

struct MyDatingProfile: Decodable {
    let profile: DatingProfileMine?
    let completeness: ProfileCompleteness?
}

/// Частичное обновление анкеты. Пол задаётся только при создании; дату рождения потом меняют в «Моих данных» раз в 90 дней.
struct DatingProfileUpdate: Encodable {
    var gender: String?
    var birthDate: String?
    var countryCode: String?
    var cityCode: String?
    var bio: String?
    var interests: [String]?
    var cuisines: [String]?
    var hobbies: [String]?
    var hidden: Bool?
    // Необязательные поля анкеты: nil здесь значит «не указано» и уходит на сервер как null.
    var heightCm: Int?
    var education: String?
    var profession: String?
    var relationshipGoal: String?
    var maritalStatus: String?
    var children: String?
    var wantsChildren: String?
    var smoking: String?
    var alcohol: String?
    var sport: String?
    /// Отправляется, только если сервер умеет вопросы в анкете (в каталоге есть prompts): старый отклонил бы лишнее поле.
    var prompts: [ProfilePromptAnswer]?
    /// Поля, которые нужно очистить (отправить null). Остальные необязательные поля с nil просто не отправляются.
    var clearing: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case gender, birthDate, countryCode, cityCode, bio, interests, cuisines, hobbies, hidden
        case heightCm, education, profession, relationshipGoal, maritalStatus, children, wantsChildren, smoking, alcohol, sport
        case prompts
    }

    /// Экран анкеты правит все необязательные поля сразу, поэтому оставленное пустым нужно именно очистить.
    static let allNullableKeys: Set<String> = [
        "heightCm", "education", "profession", "relationshipGoal", "maritalStatus",
        "children", "wantsChildren", "smoking", "alcohol", "sport",
    ]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(countryCode, forKey: .countryCode)
        try container.encodeIfPresent(cityCode, forKey: .cityCode)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(interests, forKey: .interests)
        try container.encodeIfPresent(cuisines, forKey: .cuisines)
        try container.encodeIfPresent(hobbies, forKey: .hobbies)
        try container.encodeIfPresent(hidden, forKey: .hidden)
        try container.encodeIfPresent(prompts, forKey: .prompts)

        try encodeNullable(heightCm, forKey: .heightCm, in: &container)
        try encodeNullable(education, forKey: .education, in: &container)
        try encodeNullable(profession, forKey: .profession, in: &container)
        try encodeNullable(relationshipGoal, forKey: .relationshipGoal, in: &container)
        try encodeNullable(maritalStatus, forKey: .maritalStatus, in: &container)
        try encodeNullable(children, forKey: .children, in: &container)
        try encodeNullable(wantsChildren, forKey: .wantsChildren, in: &container)
        try encodeNullable(smoking, forKey: .smoking, in: &container)
        try encodeNullable(alcohol, forKey: .alcohol, in: &container)
        try encodeNullable(sport, forKey: .sport, in: &container)
    }

    /// Заданное значение отправляем как есть, nil — только если поле явно очищают: иначе сервер поймёт
    /// отсутствие ключа как «не меняй», что и нужно при частичном сохранении.
    private func encodeNullable<T: Encodable>(_ value: T?, forKey key: CodingKeys, in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else if clearing.contains(key.stringValue) {
            try container.encodeNil(forKey: key)
        }
    }
}

struct DailyLimits: Decodable, Hashable {
    let likesPerDay: Int
    let likesLeft: Int
    /// Первые сообщения тем, с кем ещё нет пары.
    let introsPerDay: Int
    let introsLeft: Int
    let resetsAt: Date
    /// Сколько свайпов ещё можно отменить сегодня. nil — сервер не умеет отмену, кнопку не показываем.
    var undoLeft: Int? = nil
}

struct Compatibility: Decodable, Hashable {
    /// 0–100.
    let score: Int
    /// До трёх причин «почему вам подходит этот человек».
    let reasons: [String]
}

struct DatingFeedCard: Decodable, Identifiable, Hashable {
    let profile: DatingProfilePublic
    let compatibility: Compatibility
    let isNew: Bool
    /// Карточка из расширенного поиска: часть фильтров для неё ослаблена.
    let expanded: Bool

    var id: String { profile.userId }

    private enum CodingKeys: String, CodingKey {
        case compatibility, isNew, expanded
    }

    init(from decoder: Decoder) throws {
        profile = try DatingProfilePublic(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        compatibility = try container.decode(Compatibility.self, forKey: .compatibility)
        isNew = try container.decode(Bool.self, forKey: .isNew)
        expanded = try container.decode(Bool.self, forKey: .expanded)
    }
}

struct DatingFeed: Decodable {
    let cards: [DatingFeedCard]
    let limits: DailyLimits
}

struct DatingUsernameSearch: Decodable {
    let cards: [DatingFeedCard]
}

enum SwipeAction: String, Encodable {
    case like = "LIKE"
    case skip = "SKIP"
}

/// Ответ на отмену свайпа: обновлённые лимиты (если сервер их прислал).
struct UndoSwipeResult: Decodable {
    let limits: DailyLimits?
}

struct SwipeResult: Decodable {
    let limits: DailyLimits
    /// Не nil, если лайк оказался взаимным, — показываем экран «вы пара».
    let match: DatingMatch?
}

struct MatchPartner: Decodable, Hashable {
    let userId: String
    let displayName: String
    let age: Int
    let cityCode: String
    let photoId: String?
}

struct DatingMatch: Decodable, Identifiable, Hashable {
    let id: String
    /// nil — чат пары удалён (пару разорвали).
    let chatId: String?
    let createdAt: Date
    let lastActivityAt: Date
    let hasMessages: Bool
    let partner: MatchPartner
}

struct IncomingIntro: Decodable, Identifiable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
    let expiresAt: Date
    let from: DatingProfilePublic
}

struct IntroRecipient: Decodable, Hashable {
    let userId: String
    let displayName: String
    let photoId: String?
}

struct SentIntro: Decodable, Identifiable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
    let expiresAt: Date
    let to: IntroRecipient
}

struct IntroInbox: Decodable {
    let incoming: [IncomingIntro]
    let sent: [SentIntro]
}

struct StageProposal: Decodable, Hashable {
    let stage: String
    let byMe: Bool
    let at: Date
}

struct JourneyStep: Decodable, Hashable {
    let stage: String
    let reachedAt: Date
}

struct JourneyChecklist: Decodable, Hashable {
    let mine: [String]
    let partner: [String]
}

struct JourneyView: Decodable {
    let matchId: String
    let stage: String
    /// Путь завершён: вернулись к поиску или пару удалили.
    let endedAt: Date?
    let proposal: StageProposal?
    let history: [JourneyStep]
    let checklist: JourneyChecklist
}

enum MeetingStatus: String, Decodable, Hashable {
    case proposed = "PROPOSED"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case cancelled = "CANCELLED"
    /// Второй предложил другое время — действует новое приглашение (replacedById).
    case rescheduled = "RESCHEDULED"
}

struct DatingMeeting: Decodable, Identifiable, Hashable {
    let id: String
    let matchId: String
    let byMe: Bool
    let startsAt: Date
    let place: String
    let note: String
    let status: MeetingStatus
    /// Приглашение без ответа, время которого прошло, — просто не состоялось.
    let expired: Bool
    let createdAt: Date
    let respondedAt: Date?
    let replacedById: String?
    /// nil — встречу не отменяли.
    let cancelledByMe: Bool?
}

struct SelfieCheck: Decodable, Hashable {
    let id: String
    let status: ModerationStatus
    let rejectReason: String?
    let createdAt: Date
}

struct VerificationStatus: Decodable {
    let verified: Bool
    let verifiedAt: Date?
    /// Модератор попросил переснять селфи: значок и анкета остаются, новое селфи принимается.
    let reverificationRequested: Bool
    /// Что написал модератор, попросив селфи.
    let reverificationReason: String?
    /// Жест, который нужно повторить на селфи. nil — селфи сейчас не нужно (есть значок или ждёт проверки).
    let gesture: SelfieGesture?
    /// Последнее отправленное селфи: по нему видно, ждёт ли оно проверки и почему отклонено.
    let latest: SelfieCheck?
}

/// Случайный жест для селфи-проверки: по нему модератор видит, что снимок сделан сейчас.
struct SelfieGesture: Decodable, Equatable {
    let code: String
    let emoji: String
    let title: String
}

/// Кого ищет человек. Остальные поля настроек поиска на сервере ленте больше не нужны: она подбирает анкеты сама,
/// а фильтры по городу, возрасту и т. п. — у сетки анкет (DatingBrowseFilters).
/// «Кого ищу» — как она видна в чужой анкете. Пустой список и nil — «не важно».
struct SearchCriteria: Codable, Hashable {
    let lookingFor: String
    let ageMin: Int
    let ageMax: Int
    let children: String?
    let cityCodes: [String]
    let maritalStatuses: [String]

    /// Подходит ли под критерии человек с такой анкетой — по пунктам (✓/✗ в чужой анкете).
    /// Те же правила, что у сервера: незаполненное поле под заданный критерий не подходит.
    func fitsAge(_ age: Int) -> Bool { (ageMin...ageMax).contains(age) }
    func fitsChildren(_ value: String?) -> Bool { children == nil || value == children }
    func fitsCity(_ cityCode: String) -> Bool { cityCodes.isEmpty || cityCodes.contains(cityCode) }
    func fitsMaritalStatus(_ value: String?) -> Bool { maritalStatuses.isEmpty || value.map(maritalStatuses.contains) == true }
}

/// Своя анкета «Кого ищу» из GET /dating/search-settings. criteriaSetAt == nil — человек её ещё не заполнял.
struct SearchCriteriaSettings: Decodable, Hashable {
    var lookingFor: String
    var ageMin: Int
    var ageMax: Int
    var children: String?
    var cityCodes: [String]
    var maritalStatuses: [String]
    var criteriaSetAt: Date?

    private enum CodingKeys: String, CodingKey {
        case lookingFor, ageMin, ageMax, children, cityCodes, maritalStatuses, criteriaSetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lookingFor = try container.decode(String.self, forKey: .lookingFor)
        ageMin = try container.decode(Int.self, forKey: .ageMin)
        ageMax = try container.decode(Int.self, forKey: .ageMax)
        children = try container.decodeIfPresent(String.self, forKey: .children)
        // Старый сервер этих полей не знает — тогда «не важно».
        cityCodes = try container.decodeIfPresent([String].self, forKey: .cityCodes) ?? []
        maritalStatuses = try container.decodeIfPresent([String].self, forKey: .maritalStatuses) ?? []
        criteriaSetAt = try container.decodeIfPresent(Date.self, forKey: .criteriaSetAt)
    }
}

/// Сохранение «Кого ищу» целиком: children уходит и как null («не важно»).
struct SearchCriteriaUpdate: Encodable {
    let lookingFor: String
    let ageMin: Int
    let ageMax: Int
    let children: String?
    let cityCodes: [String]
    let maritalStatuses: [String]

    private enum CodingKeys: String, CodingKey {
        case lookingFor, ageMin, ageMax, children, cityCodes, maritalStatuses
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lookingFor, forKey: .lookingFor)
        try container.encode(ageMin, forKey: .ageMin)
        try container.encode(ageMax, forKey: .ageMax)
        try container.encode(children, forKey: .children)
        try container.encode(cityCodes, forKey: .cityCodes)
        try container.encode(maritalStatuses, forKey: .maritalStatuses)
    }
}

struct DatingSearchSettings: Codable, Hashable {
    var lookingFor: String
    /// Инкогнито: анкету видят только те, кого вы лайкнули. nil — сервер не знает этой настройки.
    var incognito: Bool? = nil
    /// Показывать другим, когда вы были в приложении («в сети», «сегодня»). nil — сервер не знает этой настройки.
    var showActivity: Bool? = nil
}

/// Фильтры сетки всех анкет. nil и пустой список — «любой». Хранятся на устройстве, на ленту не влияют.
struct DatingBrowseFilters: Codable, Equatable {
    /// nil — тот пол, что человек ищет («Кого ищу»).
    var gender: String?
    var cityCode: String?
    /// Не дальше N км — работает, только если включена геопозиция.
    var maxDistanceKm: Int?
    var smoking: [String] = []
    var alcohol: [String] = []
    var ageMin: Int?
    var ageMax: Int?
    var heightMin: Int?
    var heightMax: Int?
    var relationshipGoals: [String] = []
    var maritalStatuses: [String] = []
    var children: String?
    var wantsChildren: [String] = []
    var education: [String] = []
    var interests: [String] = []

    /// Сколько фильтров задано — число на кнопке «Фильтры». Возраст и рост считаются по одному.
    var activeCount: Int {
        let set: [Bool] = [
            gender != nil, cityCode != nil, maxDistanceKm != nil, ageMin != nil || ageMax != nil, heightMin != nil || heightMax != nil,
            !relationshipGoals.isEmpty, !maritalStatuses.isEmpty, children != nil, !wantsChildren.isEmpty,
            !education.isEmpty, !interests.isEmpty, !smoking.isEmpty, !alcohol.isEmpty,
        ]
        return set.filter { $0 }.count
    }

    /// Параметры GET /dating/browse: списки — через запятую, незаданное не отправляется.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value { items.append(URLQueryItem(name: name, value: value)) }
        }
        func add(_ name: String, _ values: [String]) {
            if !values.isEmpty { items.append(URLQueryItem(name: name, value: values.joined(separator: ","))) }
        }
        add("gender", gender)
        add("cityCode", cityCode)
        add("maxDistanceKm", maxDistanceKm.map(String.init))
        add("smoking", smoking)
        add("alcohol", alcohol)
        add("ageMin", ageMin.map(String.init))
        add("ageMax", ageMax.map(String.init))
        add("heightMin", heightMin.map(String.init))
        add("heightMax", heightMax.map(String.init))
        add("relationshipGoals", relationshipGoals)
        add("maritalStatuses", maritalStatuses)
        add("children", children)
        add("wantsChildren", wantsChildren)
        add("education", education)
        add("interests", interests)
        return items
    }
}

/// Сохранённые на устройстве фильтры прошлой версии: новых полей в них нет — читаем их как «не важно»,
/// чтобы после обновления фильтры не сбрасывались.
extension DatingBrowseFilters {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        cityCode = try container.decodeIfPresent(String.self, forKey: .cityCode)
        maxDistanceKm = try container.decodeIfPresent(Int.self, forKey: .maxDistanceKm)
        smoking = try container.decodeIfPresent([String].self, forKey: .smoking) ?? []
        alcohol = try container.decodeIfPresent([String].self, forKey: .alcohol) ?? []
        ageMin = try container.decodeIfPresent(Int.self, forKey: .ageMin)
        ageMax = try container.decodeIfPresent(Int.self, forKey: .ageMax)
        heightMin = try container.decodeIfPresent(Int.self, forKey: .heightMin)
        heightMax = try container.decodeIfPresent(Int.self, forKey: .heightMax)
        relationshipGoals = try container.decodeIfPresent([String].self, forKey: .relationshipGoals) ?? []
        maritalStatuses = try container.decodeIfPresent([String].self, forKey: .maritalStatuses) ?? []
        children = try container.decodeIfPresent(String.self, forKey: .children)
        wantsChildren = try container.decodeIfPresent([String].self, forKey: .wantsChildren) ?? []
        education = try container.decodeIfPresent([String].self, forKey: .education) ?? []
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case gender, cityCode, maxDistanceKm, smoking, alcohol, ageMin, ageMax, heightMin, heightMax
        case relationshipGoals, maritalStatuses, children, wantsChildren, education, interests
    }
}

/// Анкета в сетке: карточка как в ленте плюс отметка «я уже лайкнул».
struct DatingBrowseCard: Decodable, Identifiable, Hashable {
    let card: DatingFeedCard
    var liked: Bool

    var id: String { card.id }

    private enum CodingKeys: String, CodingKey {
        case liked
    }

    init(from decoder: Decoder) throws {
        card = try DatingFeedCard(from: decoder)
        liked = try decoder.container(keyedBy: CodingKeys.self).decode(Bool.self, forKey: .liked)
    }
}

/// Анкета из «Вас лайкнули»: карточка как в ленте и когда поставлен лайк.
struct DatingLikedCard: Decodable, Identifiable, Hashable {
    let card: DatingFeedCard
    let likedAt: Date

    var id: String { card.id }

    private enum CodingKeys: String, CodingKey {
        case likedAt
    }

    init(from decoder: Decoder) throws {
        card = try DatingFeedCard(from: decoder)
        likedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .likedAt)
    }
}

struct DatingLikedMe: Decodable {
    let cards: [DatingLikedCard]
}

struct DatingBrowsePage: Decodable {
    let cards: [DatingBrowseCard]
    /// nil — анкет больше нет.
    let nextCursor: String?
}

struct CommunityRules: Decodable {
    let version: String
    let rules: [String]
}

enum ReportCategory: String, CaseIterable, Identifiable, Encodable {
    case fake = "FAKE"
    case spam = "SPAM"
    case harassment = "HARASSMENT"
    case inappropriateContent = "INAPPROPRIATE_CONTENT"
    case scam = "SCAM"
    case underage = "UNDERAGE"
    case other = "OTHER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fake: return String(localized: "Фейковая анкета")
        case .spam: return String(localized: "Спам и реклама")
        case .harassment: return String(localized: "Оскорбления и преследование")
        case .inappropriateContent: return String(localized: "Непристойный контент")
        case .scam: return String(localized: "Просит деньги, мошенничество")
        case .underage: return String(localized: "Несовершеннолетний")
        case .other: return String(localized: "Другое")
        }
    }
}

struct EmergencyNumber: Decodable, Identifiable, Hashable {
    let service: String
    let number: String

    var id: String { number }
}

enum SosStatus: String, Decodable, Hashable {
    case open = "OPEN"
    case closed = "CLOSED"
}

struct SosAlert: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    let accuracyM: Double?
    let note: String
    let withUserId: String?
    let status: SosStatus
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    /// Когда пришла последняя геопозиция; nil — у старых ответов сервера.
    var lastLocationAt: Date? = nil
    /// Ссылка на карту — открывается и в Картах, и в браузере.
    let mapsUrl: String
}

struct SosTrackPoint: Decodable, Hashable {
    let latitude: Double
    let longitude: Double
    let accuracyM: Double?
    let recordedAt: Date
}

struct SosTrack: Decodable {
    let points: [SosTrackPoint]
}

struct SosRaised: Decodable {
    let alert: SosAlert
    let emergencyNumbers: [EmergencyNumber]
}

/// Дата рождения в анкете — календарный день без времени и часового пояса («ГГГГ-ММ-ДД»),
/// поэтому разбирается и собирается отдельно от ISO8601Coding, который работает с моментами времени.
enum CalendarDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}

enum DatingLimits {
    static let maxPhotos = 6
    static let maxInterests = 10
    static let maxHobbies = 10
    static let maxCuisines = 8
    static let maxBioLength = 500
    static let maxTrustedContacts = 3
    static let minHeightCm = 120
    static let maxHeightCm = 230
    static let minAge = 18
    static let maxAge = 100
    static let maxDistanceKm = 500
    static let maxPrompts = 3
    static let maxPromptAnswerLength = 200
    static let maxVoiceIntroSec = 30
}
