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

class MultiplayerManager: NSObject {

    static let shared = MultiplayerManager()

    weak var delegate: MultiplayerManagerDelegate?

    private let serviceType = "minirace"

    private let peerID = MCPeerID(
        displayName: UIDevice.current.name
    )

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private override init() {
        super.init()

        session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        session.delegate = self
    }

    func startHosting() {
        stopDiscovery()

        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["game": "MiniRacing"],
            serviceType: serviceType
        )

        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func startJoining() {
        stopDiscovery()

        browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )

        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()

        advertiser = nil
        browser = nil
    }

    func disconnect() {
        stopDiscovery()
        session.disconnect()
    }

    func connectedPlayers() -> [String] {
        return session.connectedPeers.map { $0.displayName }
    }

    func sendPosition(x: CGFloat, y: CGFloat, angle: CGFloat) {
        guard !session.connectedPeers.isEmpty else {
            return
        }

        let packet: [String: Any] = [
            "x": Double(x),
            "y": Double(y),
            "angle": Double(angle)
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
            print("Send error: \(error.localizedDescription)")
        }
    }
}

extension MultiplayerManager: MCSessionDelegate {

    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        DispatchQueue.main.async {
            self.delegate?.multiplayerPeerChanged()
        }
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        guard
            let packet = try? JSONSerialization.jsonObject(
                with: data,
                options: []
            ) as? [String: Any],
            let x = packet["x"] as? Double,
            let y = packet["y"] as? Double,
            let angle = packet["angle"] as? Double
        else {
            return
        }

        DispatchQueue.main.async {
            self.delegate?.multiplayerReceivedPosition(
                from: peerID.displayName,
                x: CGFloat(x),
                y: CGFloat(y),
                angle: CGFloat(angle)
            )
        }
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
}

extension MultiplayerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }
}

extension MultiplayerManager: MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard session.connectedPeers.count < 3 else {
            return
        }

        browser.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 15
        )
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {}
}