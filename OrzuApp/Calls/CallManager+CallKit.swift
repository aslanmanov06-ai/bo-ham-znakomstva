import AVFoundation
import CallKit
import Foundation
import PushKit
import os

// CXProvider создан с queue: nil, а PKPushRegistry — с очередью .main, поэтому все колбэки приходят на главном потоке
// и MainActor.assumeIsolated здесь корректен.

extension CallManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            finishLocally(reason: "hangup", reportToCallKit: false)
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated {
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            Task {
                if await performAnswer() {
                    action.fulfill()
                } else {
                    action.fail()
                }
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            performEnd()
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            setMuted(action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            audioSessionDidActivate(audioSession)
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            audioSessionDidDeactivate(audioSession)
        }
    }
}

extension CallManager: PKPushRegistryDelegate {
    func userDidLogIn() {
        isLoggedIn = true
        registerVoipTokenIfPossible()
    }

    /// Вызывать до очистки токенов авторизации — DELETE /devices требует валидный access token.
    func userWillLogOut() async {
        isLoggedIn = false
        endCall()
        guard let voipToken else { return }
        do {
            try await APIClient.shared.unregisterDevice(token: voipToken)
        } catch {
            logger.error("Не удалось отвязать VoIP-токен: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated {
            voipToken = token
            registerVoipTokenIfPossible()
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        MainActor.assumeIsolated {
            voipToken = nil
        }
    }

    /// iOS требует показать звонок в CallKit на КАЖДЫЙ VoIP-push, ещё до вызова completion, — иначе система
    /// завершает приложение, а после нескольких нарушений перестаёт доставлять ему VoIP-push вовсе.
    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        let callJSON = payload.dictionaryPayload["call"] as? [String: Any] ?? [:]
        MainActor.assumeIsolated {
            guard let incoming = IncomingCall(json: callJSON), TokenStore.shared.accessToken != nil else {
                reportAndImmediatelyEnd(uuid: UUID(), completion: completion)
                return
            }
            reportIncoming(incoming, completion: completion)
        }
    }

    private func registerVoipTokenIfPossible() {
        guard isLoggedIn, let voipToken else { return }
        Task {
            do {
                try await APIClient.shared.registerDevice(token: voipToken, kind: "VOIP")
            } catch {
                logger.error("Не удалось зарегистрировать VoIP-токен: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
