import XCTest
@testable import OrzuApp

/// JSON в тестах — ответы живого backend (GET /dating/…): модели должны разбирать именно их.
final class DatingModelsTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        ISO8601Coding.makeDecoder()
    }

    func testDecodesOwnProfile() throws {
        let json = Data("""
        {"profile":{"userId":"9ca6550c-6562-43d4-b3c5-c3102d6455a0","displayName":"Тимур","age":30,"gender":"MALE",
         "countryCode":"TJ","cityCode":"dushanbe","heightCm":180,"bio":"Люблю горы","interests":["travel","books"],
         "education":"HIGHER","profession":"Инженер","relationshipGoal":"MARRIAGE","maritalStatus":"NEVER_MARRIED",
         "children":"NONE","wantsChildren":"YES","smoking":"NEVER","alcohol":"NEVER","sport":"OFTEN",
         "cuisines":["tajik"],"hobbies":["hiking"],"photoIds":[],"videoId":null,"verified":false,
         "photos":[{"attachmentId":"p1","status":"PENDING","rejectReason":null}],"video":null,"inCouple":false,
         "birthDate":"1996-04-12","hidden":false,"visibleToOthers":false,
         "visibilityIssues":["NOT_VERIFIED","NO_APPROVED_PHOTOS"],"needsReverification":false,"hasLocation":false},
         "completeness":{"percent":87,"missing":["photos","video"]}}
        """.utf8)

        let response = try decoder().decode(MyDatingProfile.self, from: json)
        let profile = try XCTUnwrap(response.profile)

        XCTAssertEqual(profile.shared.displayName, "Тимур")
        XCTAssertEqual(profile.shared.heightCm, 180)
        XCTAssertEqual(profile.birthDate, "1996-04-12")
        XCTAssertEqual(profile.photos.first?.status, .pending)
        XCTAssertEqual(profile.visibilityIssues, [.notVerified, .noApprovedPhotos])
        XCTAssertEqual(response.completeness?.percent, 87)
    }

    func testDecodesEmptyProfile() throws {
        let json = Data(#"{"profile":null,"completeness":null}"#.utf8)

        let response = try decoder().decode(MyDatingProfile.self, from: json)

        XCTAssertNil(response.profile)
    }

    /// Карточка ленты — публичная анкета плюс совместимость, расстояние и пометки.
    func testDecodesFeedCard() throws {
        let json = Data("""
        {"cards":[{"userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ",
          "cityCode":"khujand","heightCm":null,"bio":"","interests":["books"],"education":null,"profession":null,
          "relationshipGoal":"MARRIAGE","maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,
          "alcohol":null,"sport":null,"cuisines":[],"hobbies":[],"photoIds":["a1"],"videoId":null,"verified":true,
          "compatibility":{"score":72,"reasons":["Общий интерес: Книги"]},"distanceKm":12,"isNew":true,"expanded":false}],
         "limits":{"likesPerDay":7,"likesLeft":6,"introsPerDay":5,"introsLeft":5,"resetsAt":"2026-09-20T19:00:00.000Z"}}
        """.utf8)

        let feed = try decoder().decode(DatingFeed.self, from: json)
        let card = try XCTUnwrap(feed.cards.first)

        XCTAssertEqual(card.id, "u2")
        XCTAssertEqual(card.profile.photoIds, ["a1"])
        XCTAssertTrue(card.profile.verified)
        XCTAssertEqual(card.compatibility.score, 72)
        XCTAssertEqual(card.profile.distanceKm, 12)
        XCTAssertTrue(card.isNew)
        XCTAssertFalse(card.expanded)
        XCTAssertEqual(feed.limits.likesLeft, 6)
    }

    /// Анкета партнёра и отправителя первого сообщения приходит с расстоянием, своя — без этого поля.
    func testPublicProfileDistance() throws {
        func profile(_ distance: String) -> Data {
            Data("""
            {"userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ","cityCode":"khujand",
             "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
             "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
             "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":true\(distance)}
            """.utf8)
        }

        let near = try decoder().decode(DatingProfilePublic.self, from: profile(#","distanceKm":3"#))
        XCTAssertEqual(near.distanceText, "3 км")

        let unknown = try decoder().decode(DatingProfilePublic.self, from: profile(#","distanceKm":null"#))
        XCTAssertNil(unknown.distanceText)

        let own = try decoder().decode(DatingProfilePublic.self, from: profile(""))
        XCTAssertNil(own.distanceKm)
    }

    /// Анкета партнёра и отправителя первого сообщения приходит с расстоянием; своя — без этого поля.
    func testProfileDistanceIsOptional() throws {
        let fields = """
        "userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ","cityCode":"khujand",
        "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
        "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
        "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":true
        """
        let partner = try decoder().decode(DatingProfilePublic.self, from: Data("{\(fields),\"distanceKm\":3}".utf8))
        let own = try decoder().decode(DatingProfilePublic.self, from: Data("{\(fields)}".utf8))

        XCTAssertEqual(partner.distanceText, "3 км")
        XCTAssertNil(own.distanceKm)
        XCTAssertNil(own.distanceText)
    }

    func testDecodesMatchAndJourneyAndMeeting() throws {
        let matchJSON = Data("""
        {"id":"m1","chatId":"c1","createdAt":"2026-09-19T10:00:00.000Z","lastActivityAt":"2026-09-20T09:00:00.000Z",
         "hasMessages":true,"partner":{"userId":"u2","displayName":"Нигина","age":28,"cityCode":"khujand","photoId":"a1"}}
        """.utf8)
        let journeyJSON = Data("""
        {"matchId":"m1","stage":"ACQUAINTANCE","endedAt":null,
         "proposal":{"stage":"FIRST_MEETING","byMe":true,"at":"2026-09-20T09:30:00.000Z"},
         "history":[{"stage":"ACQUAINTANCE","reachedAt":"2026-09-19T10:00:00.000Z"}],
         "checklist":{"mine":["public_place"],"partner":[]}}
        """.utf8)
        let meetingJSON = Data("""
        {"id":"mt1","matchId":"m1","byMe":true,"startsAt":"2026-09-22T13:30:00.000Z","place":"Кафе «Рохат»",
         "note":"У входа","status":"PROPOSED","expired":false,"createdAt":"2026-09-20T09:40:00.000Z",
         "respondedAt":null,"replacedById":null,"cancelledByMe":null}
        """.utf8)

        let match = try decoder().decode(DatingMatch.self, from: matchJSON)
        let journey = try decoder().decode(JourneyView.self, from: journeyJSON)
        let meeting = try decoder().decode(DatingMeeting.self, from: meetingJSON)

        XCTAssertEqual(match.partner.displayName, "Нигина")
        XCTAssertTrue(match.hasMessages)
        XCTAssertEqual(journey.proposal?.stage, "FIRST_MEETING")
        XCTAssertEqual(journey.checklist.mine, ["public_place"])
        XCTAssertEqual(meeting.status, .proposed)
        XCTAssertNil(meeting.cancelledByMe)
    }

    func testDecodesIncomingIntro() throws {
        let json = Data("""
        {"incoming":[{"id":"i1","text":"Привет!","createdAt":"2026-09-20T09:00:00.000Z",
          "expiresAt":"2026-09-21T09:00:00.000Z","from":{"userId":"u2","displayName":"Нигина","age":28,
          "gender":"FEMALE","countryCode":"TJ","cityCode":"khujand","heightCm":null,"bio":"","interests":[],
          "education":null,"profession":null,"relationshipGoal":null,"maritalStatus":null,"children":null,
          "wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,"cuisines":[],"hobbies":[],
          "photoIds":["a1"],"videoId":null,"verified":true}}],
         "sent":[{"id":"i2","text":"Здравствуйте","createdAt":"2026-09-20T08:00:00.000Z",
          "expiresAt":"2026-09-21T08:00:00.000Z","to":{"userId":"u3","displayName":"Мадина","photoId":null}}]}
        """.utf8)

        let inbox = try decoder().decode(IntroInbox.self, from: json)

        XCTAssertEqual(inbox.incoming.first?.from.displayName, "Нигина")
        XCTAssertEqual(inbox.sent.first?.to.userId, "u3")
        XCTAssertNil(inbox.sent.first?.to.photoId)
    }

    func testDecodesCatalogAndFindsNames() throws {
        let json = Data("""
        {"journey":{"stages":[{"code":"ACQUAINTANCE","name":"Знакомство","description":"Переписываетесь","questions":["Вопрос?"]}],
          "checklist":[{"code":"public_place","name":"Встреча в людном месте"}]},
         "countries":[{"code":"TJ","name":"Таджикистан","cities":[{"code":"dushanbe","name":"Душанбе"}]}],
         "interests":[{"code":"books","name":"Книги"}],"hobbies":[],"cuisines":[],
         "genders":[{"code":"MALE","name":"Мужчина"}],"relationshipGoals":[{"code":"MARRIAGE","name":"Брак и семья"}],
         "maritalStatuses":[],"children":[],"wantsChildren":[],"education":[],"habitFrequencies":[]}
        """.utf8)

        let catalog = try decoder().decode(DatingCatalog.self, from: json)

        XCTAssertEqual(catalog.cityName(countryCode: "TJ", cityCode: "dushanbe"), "Душанбе")
        XCTAssertEqual(catalog.stage("ACQUAINTANCE")?.name, "Знакомство")
        XCTAssertEqual(catalog.relationshipGoals.name(of: "MARRIAGE"), "Брак и семья")
        // Незнакомый код не должен исчезать из интерфейса — показываем его как есть.
        XCTAssertEqual(catalog.cityName(countryCode: "TJ", cityCode: "unknown"), "unknown")
    }

    /// Незаполненное поле анкеты нельзя просто пропустить: сервер поймёт пропуск как «не менять».
    func testProfileUpdateClearsOnlyRequestedFields() throws {
        var update = DatingProfileUpdate()
        update.bio = "Обо мне"
        update.heightCm = nil
        update.education = "HIGHER"
        update.clearing = DatingProfileUpdate.allNullableKeys

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(update)) as? [String: Any])

        XCTAssertEqual(object["bio"] as? String, "Обо мне")
        XCTAssertEqual(object["education"] as? String, "HIGHER")
        XCTAssertTrue(object["heightCm"] is NSNull)
        // Пол и дата рождения задаются только при создании — иначе их вообще нет в запросе.
        XCTAssertNil(object["gender"])
        XCTAssertNil(object["birthDate"])
    }

    func testProfileUpdateSkipsUntouchedNullableFields() throws {
        var update = DatingProfileUpdate()
        update.hidden = true

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(update)) as? [String: Any])

        XCTAssertEqual(object as NSDictionary, ["hidden": true] as NSDictionary)
    }

    /// «Кого ищу» меняется частичным PATCH: сохранённые раньше поля настроек сервер должен оставить как есть.
    func testSearchSettingsSendOnlyLookingFor() throws {
        let json = Data("""
        {"lookingFor":"FEMALE","ageMin":25,"ageMax":35,"heightMin":null,"heightMax":null,"onlyMyCity":false,
         "maxDistanceKm":null,"relationshipGoals":[],"interests":[],"children":null,"wantsChildren":[],
         "habitsCompatible":false,"excludeSeen":true,"expandSearch":true}
        """.utf8)

        let settings = try decoder().decode(DatingSearchSettings.self, from: json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(settings)) as? [String: Any])

        XCTAssertEqual(settings.lookingFor, "FEMALE")
        XCTAssertEqual(object.keys.sorted(), ["lookingFor"])
    }

    func testCalendarDateRoundTrip() throws {
        let date = try XCTUnwrap(CalendarDate.date(from: "1996-04-12"))

        XCTAssertEqual(CalendarDate.string(from: date), "1996-04-12")
        XCTAssertNil(CalendarDate.date(from: "12.04.1996"))
    }

    func testDecodesVerificationStatus() throws {
        let json = Data("""
        {"verified":false,"verifiedAt":null,
         "latest":{"id":"s1","status":"REJECTED","rejectReason":"Нужно новое селфи, а не фото из анкеты",
         "createdAt":"2026-09-20T09:00:00.000Z"}}
        """.utf8)

        let status = try decoder().decode(VerificationStatus.self, from: json)

        XCTAssertFalse(status.verified)
        XCTAssertEqual(status.latest?.status, .rejected)
        XCTAssertEqual(status.latest?.rejectReason, "Нужно новое селфи, а не фото из анкеты")
    }
}
