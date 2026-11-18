
import SpriteKit
import UIKit

private final class RacingCar: SKNode {
    private let body: SKShapeNode
    private let window: SKShapeNode

    init(color: UIColor) {
        body = SKShapeNode(
            rectOf: CGSize(width: 25, height: 43),
            cornerRadius: 7
        )
        window = SKShapeNode(
            rectOf: CGSize(width: 15, height: 13),
            cornerRadius: 3
        )

        super.init()

        body.fillColor = color
        body.strokeColor = .white
        body.lineWidth = 1.5

        window.fillColor = UIColor(white: 0.12, alpha: 1)
        window.strokeColor = .clear
        window.position = CGPoint(x: 0, y: 7)

        addChild(body)
        addChild(window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class GameScene: SKScene, MultiplayerManagerDelegate {

    private enum GameMode {
        case menu
        case offline
        case online
    }

    private var mode: GameMode = .menu
    private let multiplayer = MultiplayerManager.shared

    private var playerCar: RacingCar?
    private var remoteCars: [String: RacingCar] = [:]
    private var botCars: [RacingCar] = []

    private var statusLabel: SKLabelNode?
    private var lapLabel: SKLabelNode?
    private var speedLabel: SKLabelNode?

    private var carPosition = CGPoint.zero
    private var carVelocity = CGVector.zero
    private var carAngle: CGFloat = 0

    private var steering: CGFloat = 0
    private var throttle: CGFloat = 0
    private var activeTouches: [ObjectIdentifier: String] = [:]

    private var lastUpdate: TimeInterval = 0
    private var lastNetworkUpdate: TimeInterval = 0

    private var lapCount = 0
    private var previousTrackAngle: CGFloat?
    private var completedTrackAngle: CGFloat = 0

    private var raceStarted = false

    private var trackCenter = CGPoint.zero
    private var trackRadiusX: CGFloat = 0
    private var trackRadiusY: CGFloat = 0

    private let backgroundColorGame = UIColor(
        red: 0.055,
        green: 0.075,
        blue: 0.09,
        alpha: 1
    )

    override func didMove(to view: SKView) {
        backgroundColor = backgroundColorGame
        multiplayer.delegate = self
        showMenu()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        if mode == .menu {
            showMenu()
            return
        }

        if oldSize.width > 0, oldSize.height > 0 {
            carPosition.x *= size.width / oldSize.width
            carPosition.y *= size.height / oldSize.height
        }

        layoutGame()
    }

    // MARK: Helpers

    private func makeLabel(
        _ text: String,
        size: CGFloat,
        color: UIColor = .white
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    private func clearScene() {
        removeAllChildren()

        playerCar = nil
        remoteCars.removeAll()
        botCars.removeAll()

        statusLabel = nil
        lapLabel = nil
        speedLabel = nil

        activeTouches.removeAll()
        steering = 0
        throttle = 0
    }

    // MARK: Menu

    private func showMenu() {
        mode = .menu
        raceStarted = false

        multiplayer.disconnect()
        clearScene()

        backgroundColor = backgroundColorGame

        let title = makeLabel(
            "MINI RACING",
            size: min(size.width * 0.075, 48)
        )
        title.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.78
        )
        addChild(title)

        let subtitle = makeLabel(
            "2D ARCADE RACING",
            size: 13,
            color: UIColor(white: 0.65, alpha: 1)
        )
        subtitle.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.68
        )
        addChild(subtitle)

        addMenuButton(
            "PLAY OFFLINE",
            name: "offline",
            y: 0.53,
            color: UIColor(red: 0.12, green: 0.55, blue: 0.9, alpha: 1)
        )

        addMenuButton(
            "HOST GAME",
            name: "host",
            y: 0.39,
            color: UIColor(red: 0.12, green: 0.62, blue: 0.4, alpha: 1)
        )

        addMenuButton(
            "JOIN GAME",
            name: "join",
            y: 0.25,
            color: UIColor(red: 0.48, green: 0.32, blue: 0.82, alpha: 1)
        )

        let footer = makeLabel(
            "LOCAL WI-FI MULTIPLAYER",
            size: 10,
            color: UIColor(white: 0.5, alpha: 1)
        )
        footer.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.08
        )
        addChild(footer)
    }

    private func addMenuButton(
        _ title: String,
        name: String,
        y: CGFloat,
        color: UIColor
    ) {
        let buttonSize = CGSize(
            width: min(size.width * 0.44, 270),
            height: min(size.height * 0.11, 48)
        )

        let button = SKShapeNode(
            rectOf: buttonSize,
            cornerRadius: 12
        )
        button.name = name
        button.position = CGPoint(
            x: size.width / 2,
            y: size.height * y
        )
        button.fillColor = color
        button.strokeColor = UIColor(white: 1, alpha: 0.25)
        button.lineWidth = 1
        addChild(button)

        let label = makeLabel(title, size: 14)
        label.name = name
        label.position = button.position
        addChild(label)
    }

    // MARK: Game setup

    private func startGame(online: Bool) {
        mode = online ? .online : .offline
        raceStarted = true

        multiplayer.stopDiscovery()
        clearScene()

        lapCount = 0
        completedTrackAngle = 0
        previousTrackAngle = nil
        lastUpdate = 0
        lastNetworkUpdate = 0

        backgroundColor = UIColor(
            red: 0.12,
            green: 0.42,
            blue: 0.22,
            alpha: 1
        )

        layoutGame()

        if !online {
            addBotCars()
        }
    }

    private func layoutGame() {
        guard mode != .menu else { return }

        childNode(withName: "trackRoot")?.removeFromParent()
        childNode(withName: "hudRoot")?.removeFromParent()
        childNode(withName: "controlsRoot")?.removeFromParent()

        trackCenter = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )

        trackRadiusX = max(90, min(size.width * 0.33, size.width / 2 - 45))
        trackRadiusY = max(55, min(size.height * 0.28, size.height / 2 - 45))

        drawTrack()

        if playerCar == nil {
            let car = RacingCar(color: UIColor(
                red: 0.1,
                green: 0.48,
                blue: 1,
                alpha: 1
            ))

            playerCar = car
            addChild(car)

            carPosition = CGPoint(
                x: trackCenter.x,
                y: trackCenter.y - trackRadiusY
            )

            carAngle = 0
            carVelocity = .zero
        }

        playerCar?.position = carPosition
        playerCar?.zRotation = carAngle

        addHUD()
        addControls()
    }

    private func drawTrack() {
        let root = SKNode()
        root.name = "trackRoot"
        root.zPosition = -10

        let outerRect = CGRect(
            x: trackCenter.x - trackRadiusX - 28,
            y: trackCenter.y - trackRadiusY - 28,
            width: (trackRadiusX + 28) * 2,
            height: (trackRadiusY + 28) * 2
        )

        let outer = SKShapeNode(ellipseIn: outerRect)
        outer.strokeColor = UIColor(white: 0.1, alpha: 1)
        outer.lineWidth = 12
        outer.fillColor = .clear
        root.addChild(outer)

        let roadRect = CGRect(
            x: trackCenter.x - trackRadiusX,
            y: trackCenter.y - trackRadiusY,
            width: trackRadiusX * 2,
            height: trackRadiusY * 2
        )

        let road = SKShapeNode(ellipseIn: roadRect)
        road.strokeColor = UIColor(
            red: 0.22,
            green: 0.24,
            blue: 0.27,
            alpha: 1
        )
        road.lineWidth = 55
        road.fillColor = .clear
        root.addChild(road)

        let innerRect = CGRect(
            x: trackCenter.x - trackRadiusX + 28,
            y: trackCenter.y - trackRadiusY + 28,
            width: max(1, (trackRadiusX - 28) * 2),
            height: max(1, (trackRadiusY - 28) * 2)
        )

        let inner = SKShapeNode(ellipseIn: innerRect)
        inner.fillColor = UIColor(
            red: 0.12,
            green: 0.42,
            blue: 0.22,
            alpha: 1
        )
        inner.strokeColor = .clear
        root.addChild(inner)

        let startLine = SKShapeNode(
            rectOf: CGSize(width: 48, height: 5)
        )
        startLine.fillColor = .white
        startLine.strokeColor = .clear
        startLine.position = CGPoint(
            x: trackCenter.x,
            y: trackCenter.y - trackRadiusY
        )
        root.addChild(startLine)

        addChild(root)
    }

    // MARK: HUD

    private func addHUD() {
        let root = SKNode()
        root.name = "hudRoot"
        root.zPosition = 30
        addChild(root)

        let lap = makeLabel("LAP 0 / 3", size: 14)
        lap.horizontalAlignmentMode = .left
        lap.position = CGPoint(x: 18, y: size.height - 25)
        lapLabel = lap
        root.addChild(lap)

        let speed = makeLabel("SPEED 0", size: 13)
        speed.horizontalAlignmentMode = .right
        speed.position = CGPoint(x: size.width - 18, y: size.height - 25)
        speedLabel = speed
        root.addChild(speed)

        let status = makeLabel(
            mode == .online ? "CONNECTING..." : "OFFLINE RACE",
            size: 10,
            color: UIColor(white: 0.85, alpha: 1)
        )
        status.position = CGPoint(
            x: size.width / 2,
            y: size.height - 25
        )
        statusLabel = status
        root.addChild(status)

        let back = makeLabel("MENU", size: 11)
        back.name = "back"
        back.position = CGPoint(
            x: size.width / 2,
            y: size.height - 48
        )
        root.addChild(back)
    }

    // MARK: Controls

    private func addControls() {
        let root = SKNode()
        root.name = "controlsRoot"
        root.zPosition = 50
        addChild(root)

        let shortSide = min(size.width, size.height)
        let buttonWidth = min(shortSide * 0.22, 82)
        let buttonHeight = min(shortSide * 0.18, 66)

        addControl(
            to: root,
            name: "left",
            title: "◀",
            position: CGPoint(x: size.width * 0.12, y: size.height * 0.19),
            width: buttonWidth,
            height: buttonHeight
        )

        addControl(
            to: root,
            name: "right",
            title: "▶",
            position: CGPoint(x: size.width * 0.25, y: size.height * 0.19),
            width: buttonWidth,
            height: buttonHeight
        )

        addControl(
            to: root,
            name: "brake",
            title: "BRAKE",
            position: CGPoint(x: size.width * 0.75, y: size.height * 0.15),
            width: buttonWidth,
            height: buttonHeight
        )

        addControl(
            to: root,
            name: "gas",
            title: "GAS",
            position: CGPoint(x: size.width * 0.88, y: size.height * 0.23),
            width: buttonWidth,
            height: buttonHeight
        )
    }

    private func addControl(
        to root: SKNode,
        name: String,
        title: String,
        position: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) {
        let button = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: 13
        )
        button.name = name
        button.position = position
        button.fillColor = UIColor(white: 1, alpha: 0.18)
        button.strokeColor = UIColor(white: 1, alpha: 0.4)
        button.lineWidth = 1
        root.addChild(button)

        let label = makeLabel(title, size: 14)
        label.name = name
        label.position = position
        root.addChild(label)
    }

    // MARK: Offline bots

    private func addBotCars() {
        let colors: [UIColor] = [.red, .yellow]

        for (index, color) in colors.enumerated() {
            let bot = RacingCar(color: color)
            let offset = CGFloat(index + 1) * 32

            bot.position = CGPoint(
                x: trackCenter.x + offset,
                y: trackCenter.y - trackRadiusY
            )
            bot.zPosition = 2

            botCars.append(bot)
            addChild(bot)

            let duration = 3.5 + Double(index)

            let path = SKAction.sequence([
                SKAction.moveBy(
                    x: trackRadiusX * 0.75,
                    y: trackRadiusY,
                    duration: duration
                ),
                SKAction.moveBy(
                    x: -trackRadiusX * 1.5,
                    y: 0,
                    duration: duration
                ),
                SKAction.moveBy(
                    x: trackRadiusX * 0.75,
                    y: -trackRadiusY,
                    duration: duration
                ),
                SKAction.moveBy(
                    x: trackRadiusX * 0.0,
                    y: 0,
                    duration: 0.1
                )
            ])

            bot.run(SKAction.repeatForever(path))
        }
    }

    // MARK: Touch handling

    private func controlName(at point: CGPoint) -> String? {
        for node in nodes(at: point) {
            var current: SKNode? = node

            while let item = current {
                if let name = item.name {
                    return name
                }
                current = item.parent
            }
        }

        return nil
    }

    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let name = controlName(at: point) else { continue }

            if mode == .menu {
                switch name {
                case "offline":
                    startGame(online: false)

                case "host":
                    startGame(online: true)
                    statusLabel?.text = "WAITING FOR PLAYERS..."
                    multiplayer.startHosting()

                case "join":
                    startGame(online: true)
                    statusLabel?.text = "SEARCHING..."
                    multiplayer.startJoining()

                default:
                    break
                }

                continue
            }

            if name == "back" {
                showMenu()
                return
            }

            if ["left", "right", "gas", "brake"].contains(name) {
                activeTouches[ObjectIdentifier(touch)] = name
                updateControlsState()
            }
        }
    }

    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        for touch in touches {
            activeTouches.removeValue(forKey: ObjectIdentifier(touch))
        }

        updateControlsState()
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        for touch in touches {
            activeTouches.removeValue(forKey: ObjectIdentifier(touch))
        }

        updateControlsState()
    }

    private func updateControlsState() {
        let values = Array(activeTouches.values)

        steering = values.contains("left") ? 1 : 0
        if values.contains("right") {
            steering = -1
        }

        throttle = values.contains("gas") ? 1 : 0
        if values.contains("brake") {
            throttle = -0.6
        }
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        guard raceStarted, mode != .menu else { return }

        var delta = currentTime - lastUpdate
        lastUpdate = currentTime

        if delta <= 0 { return }
        delta = min(delta, 1.0 / 30.0)

        updatePlayer(delta: CGFloat(delta))
        updateLapProgress()
        updateHUD()

        if mode == .online,
           currentTime - lastNetworkUpdate >= 0.08 {
            multiplayer.sendPosition(
                x: carPosition.x / max(size.width, 1),
                y: carPosition.y / max(size.height, 1),
                angle: carAngle
            )
            lastNetworkUpdate = currentTime
        }
    }

    private func updatePlayer(delta: CGFloat) {
        let speed = sqrt(
            carVelocity.dx * carVelocity.dx +
            carVelocity.dy * carVelocity.dy
        )

        if speed > 8 {
            carAngle += steering * delta * min(speed / 45, 2.4)
        }

        let acceleration: CGFloat = 190

        carVelocity.dx += cos(carAngle) * throttle * acceleration * delta
        carVelocity.dy += sin(carAngle) * throttle * acceleration * delta

        let drag: CGFloat = throttle == 0 ? 0.985 : 0.996
        carVelocity.dx *= drag
        carVelocity.dy *= drag

        let currentSpeed = sqrt(
            carVelocity.dx * carVelocity.dx +
            carVelocity.dy * carVelocity.dy
        )

        let maxSpeed: CGFloat = 260

        if currentSpeed > maxSpeed {
            let factor = maxSpeed / currentSpeed
            carVelocity.dx *= factor
            carVelocity.dy *= factor
        }

        carPosition.x += carVelocity.dx * delta
        carPosition.y += carVelocity.dy * delta

        let dx = (carPosition.x - trackCenter.x) / max(trackRadiusX, 1)
        let dy = (carPosition.y - trackCenter.y) / max(trackRadiusY, 1)
        let distance = sqrt(dx * dx + dy * dy)

        if distance > 1.13 {
            carVelocity.dx *= 0.88
            carVelocity.dy *= 0.88
        }

        if distance < 0.55 {
            carVelocity.dx *= 0.94
            carVelocity.dy *= 0.94
        }

        playerCar?.position = carPosition
        playerCar?.zRotation = carAngle
    }

    private func updateLapProgress() {
        let dx = (carPosition.x - trackCenter.x) / max(trackRadiusX, 1)
        let dy = (carPosition.y - trackCenter.y) / max(trackRadiusY, 1)

        let angle = atan2(dy, dx)

        if let previous = previousTrackAngle {
            var difference = angle - previous

            if difference < -.pi {
                difference += .pi * 2
            } else if difference > .pi {
                difference -= .pi * 2
            }

            completedTrackAngle += difference

            if completedTrackAngle >= .pi * 2 {
                completedTrackAngle -= .pi * 2
                lapCount += 1

                if lapCount >= 3 {
                    finishRace()
                }
            }
        }

        previousTrackAngle = angle
    }

    private func updateHUD() {
        let speed = sqrt(
            carVelocity.dx * carVelocity.dx +
            carVelocity.dy * carVelocity.dy
        )

        speedLabel?.text = "SPEED \(Int(speed / 2))"
        lapLabel?.text = "LAP \(lapCount) / 3"
    }

    // MARK: Finish

    private func finishRace() {
        raceStarted = false
        carVelocity = .zero

        let overlay = SKNode()
        overlay.name = "finishOverlay"
        overlay.zPosition = 100

        let title = makeLabel(
            "YOU FINISHED!",
            size: min(size.width * 0.065, 38),
            color: .yellow
        )
        title.position = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )
        overlay.addChild(title)

        let instruction = makeLabel(
            "TAP MENU TO RETURN",
            size: 13
        )
        instruction.position = CGPoint(
            x: size.width / 2,
            y: size.height / 2 - 40
        )
        overlay.addChild(instruction)

        addChild(overlay)
    }

    // MARK: Multiplayer

    func multiplayerPeerChanged() {
        let players = multiplayer.connectedPlayers()
        statusLabel?.text = "\(players.count + 1) PLAYER(S) CONNECTED"

        let colors: [UIColor] = [.red, .yellow, .purple]

        for (index, name) in players.enumerated() {
            if remoteCars[name] == nil {
                let car = RacingCar(color: colors[index % colors.count])
                car.zPosition = 5
                remoteCars[name] = car
                addChild(car)
            }
        }
    }

    func multiplayerReceivedPosition(
        from player: String,
        x: CGFloat,
        y: CGFloat,
        angle: CGFloat
    ) {
        guard mode == .online else { return }

        if remoteCars[player] == nil {
            let car = RacingCar(color: .red)
            car.zPosition = 5
            remoteCars[player] = car
            addChild(car)
        }

        remoteCars[player]?.position = CGPoint(
            x: x * size.width,
            y: y * size.height
        )
        remoteCars[player]?.zRotation = angle
    }
}
