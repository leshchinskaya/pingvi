import CryptoKit
import Foundation
import Security

public struct PingviPairingOffer: Codable, Equatable, Sendable {
    public let version: Int
    public let serviceID: String
    public let macName: String
    public let serverPublicKey: Data
    public let secret: Data
    public let expiresAt: Date

    public init(
        version: Int = PingviProtocol.currentVersion,
        serviceID: String,
        macName: String,
        serverPublicKey: Data,
        secret: Data,
        expiresAt: Date
    ) {
        self.version = version
        self.serviceID = serviceID
        self.macName = macName
        self.serverPublicKey = serverPublicKey
        self.secret = secret
        self.expiresAt = expiresAt
    }

    public var url: URL? {
        guard let encoded = try? JSONEncoder.pingvi.encode(self).base64URLString else { return nil }
        return URL(string: "pingvi://pair?v=1&data=\(encoded)")
    }

    public static func decode(url: URL, now: Date = Date()) throws -> Self {
        guard url.scheme == "pingvi", url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let data = Data(base64URLString: value),
              let offer = try? JSONDecoder.pingvi.decode(Self.self, from: data) else {
            throw PingviLinkError.invalidPairingOffer
        }
        guard offer.version == PingviProtocol.currentVersion else {
            throw PingviLinkError.incompatibleVersion(offer.version)
        }
        guard offer.expiresAt > now else { throw PingviLinkError.pairingExpired }
        guard offer.secret.count == 32, offer.serverPublicKey.count == 32, !offer.serviceID.isEmpty else {
            throw PingviLinkError.invalidPairingOffer
        }
        return offer
    }
}

public struct PingviPairRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let deviceID: String
    public let deviceName: String
    public let clientPublicKey: Data
    public let nonce: Data
    public let proof: Data
}

public struct PingviPairResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let deviceID: String
    public let proof: Data
}

public struct PingviClientHello: Codable, Equatable, Sendable {
    public let version: Int
    public let deviceID: String
    public let nonce: Data
    public let proof: Data
}

public struct PingviServerHello: Codable, Equatable, Sendable {
    public let version: Int
    public let nonce: Data
    public let proof: Data
}

public struct PingviDeviceIdentity: Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let privateKey: Data

    public init(deviceID: String = UUID().uuidString, deviceName: String, privateKey: Data? = nil) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.privateKey = privateKey ?? Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    }

    public var publicKey: Data? {
        try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey).publicKey.rawRepresentation
    }
}

public enum PingviCrypto {
    public static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        precondition(status == errSecSuccess, "Secure random number generation failed")
        return data
    }

    public static func makePairingOffer(identity: PingviDeviceIdentity, serviceID: String, lifetime: TimeInterval = 300, now: Date = Date()) throws -> PingviPairingOffer {
        guard let publicKey = identity.publicKey else { throw PingviLinkError.invalidPairingOffer }
        return PingviPairingOffer(
            serviceID: serviceID,
            macName: identity.deviceName,
            serverPublicKey: publicKey,
            secret: randomBytes(count: 32),
            expiresAt: now.addingTimeInterval(lifetime)
        )
    }

    public static func makePairRequest(offer: PingviPairingOffer, client: PingviDeviceIdentity, nonce: Data? = nil) throws -> (request: PingviPairRequest, pairingKey: Data) {
        guard offer.version == PingviProtocol.currentVersion,
              let clientPublicKey = client.publicKey else {
            throw PingviLinkError.invalidPairingOffer
        }
        let requestNonce = nonce ?? randomBytes(count: 32)
        let transcript = pairTranscript(
            serviceID: offer.serviceID,
            deviceID: client.deviceID,
            clientPublicKey: clientPublicKey,
            nonce: requestNonce
        )
        let proof = mac(data: transcript, keyData: offer.secret)
        let pairingKey = try derivePairingKey(
            privateKey: client.privateKey,
            peerPublicKey: offer.serverPublicKey,
            secret: offer.secret,
            serviceID: offer.serviceID,
            deviceID: client.deviceID
        )
        return (
            PingviPairRequest(
                version: PingviProtocol.currentVersion,
                deviceID: client.deviceID,
                deviceName: client.deviceName,
                clientPublicKey: clientPublicKey,
                nonce: requestNonce,
                proof: proof
            ),
            pairingKey
        )
    }

    public static func acceptPairRequest(
        _ request: PingviPairRequest,
        offer: PingviPairingOffer,
        server: PingviDeviceIdentity,
        now: Date = Date()
    ) throws -> (response: PingviPairResponse, pairingKey: Data) {
        guard request.version == PingviProtocol.currentVersion else {
            throw PingviLinkError.incompatibleVersion(request.version)
        }
        guard offer.expiresAt > now else { throw PingviLinkError.pairingExpired }
        let transcript = pairTranscript(
            serviceID: offer.serviceID,
            deviceID: request.deviceID,
            clientPublicKey: request.clientPublicKey,
            nonce: request.nonce
        )
        guard validMAC(request.proof, data: transcript, keyData: offer.secret) else {
            throw PingviLinkError.authenticationFailed
        }
        let pairingKey = try derivePairingKey(
            privateKey: server.privateKey,
            peerPublicKey: request.clientPublicKey,
            secret: offer.secret,
            serviceID: offer.serviceID,
            deviceID: request.deviceID
        )
        let responseProof = mac(data: responseTranscript(deviceID: request.deviceID, nonce: request.nonce), keyData: pairingKey)
        return (
            PingviPairResponse(version: PingviProtocol.currentVersion, deviceID: server.deviceID, proof: responseProof),
            pairingKey
        )
    }

    public static func verifyPairResponse(_ response: PingviPairResponse, request: PingviPairRequest, pairingKey: Data) throws {
        guard response.version == PingviProtocol.currentVersion,
              validMAC(response.proof, data: responseTranscript(deviceID: request.deviceID, nonce: request.nonce), keyData: pairingKey) else {
            throw PingviLinkError.authenticationFailed
        }
    }

    public static func makeClientHello(deviceID: String, pairingKey: Data, nonce: Data? = nil) -> PingviClientHello {
        let value = nonce ?? randomBytes(count: 32)
        return PingviClientHello(
            version: PingviProtocol.currentVersion,
            deviceID: deviceID,
            nonce: value,
            proof: mac(data: helloTranscript(role: "client", deviceID: deviceID, first: value, second: Data()), keyData: pairingKey)
        )
    }

    public static func acceptClientHello(_ hello: PingviClientHello, pairingKey: Data, serverNonce: Data? = nil) throws -> (PingviServerHello, SymmetricKey) {
        guard hello.version == PingviProtocol.currentVersion else {
            throw PingviLinkError.incompatibleVersion(hello.version)
        }
        guard validMAC(
            hello.proof,
            data: helloTranscript(role: "client", deviceID: hello.deviceID, first: hello.nonce, second: Data()),
            keyData: pairingKey
        ) else { throw PingviLinkError.authenticationFailed }
        let nonce = serverNonce ?? randomBytes(count: 32)
        let proof = mac(
            data: helloTranscript(role: "server", deviceID: hello.deviceID, first: hello.nonce, second: nonce),
            keyData: pairingKey
        )
        let key = sessionKey(pairingKey: pairingKey, clientNonce: hello.nonce, serverNonce: nonce)
        return (PingviServerHello(version: PingviProtocol.currentVersion, nonce: nonce, proof: proof), key)
    }

    public static func acceptServerHello(_ hello: PingviServerHello, clientHello: PingviClientHello, pairingKey: Data) throws -> SymmetricKey {
        guard hello.version == PingviProtocol.currentVersion,
              validMAC(
                hello.proof,
                data: helloTranscript(role: "server", deviceID: clientHello.deviceID, first: clientHello.nonce, second: hello.nonce),
                keyData: pairingKey
              ) else { throw PingviLinkError.authenticationFailed }
        return sessionKey(pairingKey: pairingKey, clientNonce: clientHello.nonce, serverNonce: hello.nonce)
    }

    public static func seal(_ data: Data, sequence: UInt64, using key: SymmetricKey) throws -> PingviSealedFrame {
        let box = try ChaChaPoly.seal(data, using: key, authenticating: sequence.data)
        return PingviSealedFrame(sequence: sequence, combined: box.combined)
    }

    public static func open(_ frame: PingviSealedFrame, using key: SymmetricKey) throws -> Data {
        do {
            return try ChaChaPoly.open(
                ChaChaPoly.SealedBox(combined: frame.combined),
                using: key,
                authenticating: frame.sequence.data
            )
        } catch {
            throw PingviLinkError.authenticationFailed
        }
    }

    private static func derivePairingKey(privateKey: Data, peerPublicKey: Data, secret: Data, serviceID: String, deviceID: String) throws -> Data {
        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            let key = shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: secret,
                sharedInfo: Data("pingvi-pair-v1|\(serviceID)|\(deviceID)".utf8),
                outputByteCount: 32
            )
            return key.withUnsafeBytes { Data($0) }
        } catch {
            throw PingviLinkError.authenticationFailed
        }
    }

    private static func sessionKey(pairingKey: Data, clientNonce: Data, serverNonce: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pairingKey),
            salt: clientNonce + serverNonce,
            info: Data("pingvi-session-v1".utf8),
            outputByteCount: 32
        )
    }

    private static func pairTranscript(serviceID: String, deviceID: String, clientPublicKey: Data, nonce: Data) -> Data {
        joined([Data("pingvi-pair-request-v1".utf8), Data(serviceID.utf8), Data(deviceID.utf8), clientPublicKey, nonce])
    }

    private static func responseTranscript(deviceID: String, nonce: Data) -> Data {
        joined([Data("pingvi-pair-response-v1".utf8), Data(deviceID.utf8), nonce])
    }

    private static func helloTranscript(role: String, deviceID: String, first: Data, second: Data) -> Data {
        joined([Data("pingvi-hello-v1".utf8), Data(role.utf8), Data(deviceID.utf8), first, second])
    }

    private static func joined(_ values: [Data]) -> Data {
        values.reduce(into: Data()) { result, value in
            result.append(UInt32(value.count).data)
            result.append(value)
        }
    }

    private static func mac(data: Data, keyData: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: keyData)))
    }

    private static func validMAC(_ candidate: Data, data: Data, keyData: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(candidate, authenticating: data, using: SymmetricKey(data: keyData))
    }
}

public struct PingviSealedFrame: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let combined: Data

    public init(sequence: UInt64, combined: Data) {
        self.sequence = sequence
        self.combined = combined
    }
}

public struct PingviReceiveCipher: Sendable {
    private let key: SymmetricKey
    private var expectedSequence: UInt64

    public init(key: SymmetricKey, expectedSequence: UInt64 = 0) {
        self.key = key
        self.expectedSequence = expectedSequence
    }

    public mutating func open(_ frame: PingviSealedFrame) throws -> Data {
        guard frame.sequence == expectedSequence else { throw PingviLinkError.replayedFrame }
        let data = try PingviCrypto.open(frame, using: key)
        expectedSequence += 1
        return data
    }
}

public struct PingviSendCipher: Sendable {
    private let key: SymmetricKey
    private var sequence: UInt64

    public init(key: SymmetricKey, sequence: UInt64 = 0) {
        self.key = key
        self.sequence = sequence
    }

    public mutating func seal(_ data: Data) throws -> PingviSealedFrame {
        let frame = try PingviCrypto.seal(data, sequence: sequence, using: key)
        sequence += 1
        return frame
    }
}

extension JSONEncoder {
    static var pingvi: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var pingvi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLString: String) {
        var value = base64URLString.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}

private extension FixedWidthInteger {
    var data: Data {
        var value = bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
