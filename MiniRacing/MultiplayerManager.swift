
import UIKit
import MultipeerConnectivity

protocol MultiplayerManagerDelegate: AnyObject {
    func multiplayerPeerChanged()

    func multiplayerReceivedPosition(
        from player: String,
        x: CGFloat,
        y: CGFloat,
        angle: CGFloat
    )
}

final class MultiplayerManager: NSObject {

    static let shared = MultiplayerManager()

    weak var delegate: MultiplayerManagerDelegate?

    private let serviceType = "minirace"

    private lazy var peerID = MCPeerID(
        displayName: UIDevice.current.name
    )

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var invitedPeers = Set<MCPeerID>()
    private var isHost = false

    private override init() {
        super.init()

        session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        session.delegate = self
    }

    // MARK: - HOST

    func startHosting() {
        stopDiscovery()

        isHost = true
        invitedPeers.removeAll()

        let newAdvertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["game": "MiniRacing"],
            serviceType: serviceType
        )

        newAdvertiser.delegate = self
        advertiser = newAdvertiser
        newAdvertiser.startAdvertisingPeer()
    }

    // MARK: - JOIN

    func startJoining() {
        stopDiscovery()

        isHost = false
        invitedPeers.removeAll()

        let newBrowser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )

        newBrowser.delegate = self
        browser = newBrowser
        newBrowser.startBrowsingForPeers()
    }

    // MARK: - DISCOVERY

    func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()

        advertiser = nil
        browser = nil
    }

    // MARK: - DISCONNECT

    func disconnect() {
        stopDiscovery()

        invitedPeers.removeAll()
        session.disconnect()

        DispatchQueue.main.async {
            self.delegate?.multiplayerPeerChanged()
        }
    }

    // MARK: - PLAYERS

    func connectedPlayers() -> [String] {
        return session.connectedPeers.map {
            $0.displayName
        }
    }

    var playerCount: Int {
        return session.connectedPeers.count + 1
    }

    // MARK: - SEND POSITION

    func sendPosition(
        x: CGFloat,
        y: CGFloat,
        angle: CGFloat
    ) {
        guard !session.connectedPeers.isEmpty else {
            return
        }

        let packet: [String: Any] = [
            "type": "position",
            "x": Double(x),
            "y": Double(y),
            "angle": Double(angle),
            "player": peerID.displayName
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: packet,
            options: []
        ) else {
            return
        }

        do {
            try session.send(
                data,
                toPeers: session.connectedPeers,
                with: .unreliable
            )
        } catch {
            print("Position send error: \(error.localizedDescription)")
        }
    }

    // MARK: - SEND MESSAGE

    func sendMessage(_ message: String) {
        guard !session.connectedPeers.isEmpty else {
            return
        }

        let packet: [String: Any] = [
            "type": "message",
            "text": message,
            "player": peerID.displayName
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: packet,
            options: []
        ) else {
            return
        }

        do {
            try session.send(
                data,
                toPeers: session.connectedPeers,
                with: .reliable
            )
        } catch {
            print("Message send error: \(error.localizedDescription)")
        }
    }

    // MARK: - RECEIVE PACKET

    private func handleReceivedPacket(
        _ data: Data,
        from peer: MCPeerID,
        in session: MCSession
    ) {
        guard
            let packet = try? JSONSerialization.jsonObject(
                with: data,
                options: []
            ) as? [String: Any],
            let type = packet["type"] as? String
        else {
            return
        }

        if type == "position" {

            guard
                let x = packet["x"] as? Double,
                let y = packet["y"] as? Double,
                let angle = packet["angle"] as? Double
            else {
                return
            }

            let playerName = peer.displayName

            // Host forwards received positions to other players.
            if isHost {
                let otherPeers = session.connectedPeers.filter {
                    $0 != peer
                }

                if !otherPeers.isEmpty {
                    do {
                        try session.send(
                            data,
                            toPeers: otherPeers,
                            with: .unreliable
                        )
                    } catch {
                        print("Relay error: \(error.localizedDescription)")
                    }
                }
            }

            DispatchQueue.main.async {
                self.delegate?.multiplayerReceivedPosition(
                    from: playerName,
                    x: CGFloat(x),
                    y: CGFloat(y),
                    angle: CGFloat(angle)
                )
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension MultiplayerManager: MCSessionDelegate {

    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        DispatchQueue.main.async {
            self.delegate?.multiplayerPeerChanged()
        }

        switch state {
        case .connected:
            print("Connected: \(peerID.displayName)")

        case .connecting:
            print("Connecting: \(peerID.displayName)")

        case .notConnected:
            print("Disconnected: \(peerID.displayName)")

        @unknown default:
            print("Unknown peer state")
        }
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        handleReceivedPacket(
            data,
            from: peerID,
            in: session
        )
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}

    func session(
        _ session: MCSession,
        didReceive certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultiplayerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let canAccept = session.connectedPeers.count < 3

        invitationHandler(
            canAccept,
            canAccept ? session : nil
        )
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        print("Advertising error: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultiplayerManager: MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard session.connectedPeers.count < 1 else {
            return
        }

        guard !invitedPeers.contains(peerID) else {
            return
        }

        guard info?["game"] == "MiniRacing" else {
            return
        }

        invitedPeers.insert(peerID)

        browser.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 20
        )
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        invitedPeers.remove(peerID)
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        print("Browsing error: \(error.localizedDescription)")
    }
}
