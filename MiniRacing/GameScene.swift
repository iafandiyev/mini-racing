import SpriteKit
import UIKit

private final class RacingCar: SKNode {

    let body: SKShapeNode
    let window: SKShapeNode

    init(color: UIColor) {
        body = SKShapeNode(rectOf: CGSize(width: 25, height: 43), cornerRadius: 7)
        window = SKShapeNode(rectOf: CGSize(width: 15, height: 13), cornerRadius: 3)

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

    private var menuNodes: [SKNode] = []
    private var controlNodes: [SKNode] = []

    private var statusLabel: SKLabelNode?
    private var lapLabel: SKLabelNode?
    private var speedLabel: SKLabelNode?

    private var carPosition = CGPoint.zero
    private var carVelocity = CGVector.zero
    private var carAngle: CGFloat = 0

    private var steering: CGFloat = 0
    private var throttle: CGFloat = 0

    private var lastUpdate: TimeInterval = 0
    private var lastNetworkUpdate: TimeInterval = 0

    private var lapCount = 0
    private var lastCheckpointY: CGFloat = 0
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
        } else {
            layoutGame()
        }
    }

    // MARK: - Menu

    private func clearScene() {
        removeAllChildren()
        menuNodes.removeAll()
        controlNodes.removeAll()
        remoteCars.removeAll()
        botCars.removeAll()

        playerCar = nil
        statusLabel = nil
        lapLabel = nil
        speedLabel = nil
    }

    private func showMenu() {
        mode = .menu
        raceStarted = false

        clearScene()
        multiplayer.disconnect()

        backgroundColor = backgroundColorGame

        let title = makeLabel(
            text: "MINI RACING",
            size: min(size.width * 0.075, 48),
            color: .white
        )

        title.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.77
        )

        addChild(title)

        let subtitle = makeLabel(
            text: "2D ARCADE RACING",
            size: 13,
            color: UIColor(white: 0.65, alpha: 1)
        )

        subtitle.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.68
        )

        addChild(subtitle)

        addMenuButton(
            title: "PLAY OFFLINE",
            name: "offline",
            position: CGPoint(x: size.width / 2, y: size.height * 0.52),
            color: UIColor(red: 0.12, green: 0.65, blue: 0.95, alpha: 1)
        )

        addMenuButton(
            title: "HOST GAME",
            name: "host",
            position: CGPoint(x: size.width / 2, y: size.height * 0.38),
            color: UIColor(red: 0.15, green: 0.72, blue: 0.48, alpha: 1)
        )

        addMenuButton(
            title: "JOIN GAME",
            name: "join",
            position: CGPoint(x: size.width / 2, y: size.height * 0.24),
            color: UIColor(red: 0.55, green: 0.38, blue: 0.9, alpha: 1)
        )

        let footer = makeLabel(
            text: "MINI RACING  •  LOCAL MULTIPLAYER",
            size: 10,
            color: UIColor(white: 0.45, alpha: 1)
        )

        footer.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.08
        )

        addChild(footer)

        let status = makeLabel(
            text: "",
            size: 12,
            color: .white
        )

        status.position = CGPoint(
            x: size.width / 2,
            y: size.height * 0.15
        )

        statusLabel = status
        addChild(status)
    }

    private func addMenuButton(
        title: String,
        name: String,
        position: CGPoint,
        color: UIColor
    ) {
        let button = SKShapeNode(
            rectOf: CGSize(
                width: min(size.width * 0.42, 260),
                height: min(size.height * 0.105, 48)
            ),
            cornerRadius: 12
        )

        button.name = name
        button.fillColor = color
        button.strokeColor = UIColor(white: 1, alpha: 0.2)
        button.lineWidth = 1
        button.position = position
        addChild(button)

        let label = makeLabel(
            text: title,
            size: 14,
            color: .white
        )

        label.name = name
        label.position = position
        addChild(label)
    }

    // MARK: - Game setup

    private func startGame(online: Bool) {
        mode = online ? .online : .offline
        raceStarted = true

        multiplayer.stopDiscovery()

        clearScene()

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
        guard mode != .menu else {
            return
        }

        removeChildren(in: children.filter {
            $0.name == "track" ||
            $0.name == "hud" ||
            $0.name == "controls"
        })

        trackCenter = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )

        trackRadiusX = size.width * 0.34
        trackRadiusY = size.height * 0.31

        drawTrack()

        if playerCar == nil {
            let car = RacingCar(color: .systemBlue)
            playerCar = car
            addChild(car)

            carPosition = CGPoint(
                x: trackCenter.x,
                y: trackCenter.y - trackRadiusY
            )

            carAngle = .pi / 2
            carVelocity = .zero
        }

        playerCar?.position = carPosition
        playerCar?.zRotation = carAngle

        addHUD()
        addControls()
    }

    private func drawTrack() {
        let track = SKNode()
        track.name = "track"
        track.zPosition = -10

        let outer = CGMutablePath()
        outer.addEllipse(in: CGRect(
            x: trackCenter.x - trackRadiusX - 28,
            y: trackCenter.y - trackRadiusY - 28,
            width: (trackRadiusX + 28) * 2,
            height: (trackRadiusY + 28) * 2
        ))

        let outerShape = SKShapeNode(path: outer)
        outerShape.strokeColor = UIColor(white: 0.12, alpha: 1)
        outerShape.lineWidth = 30
        outerShape.fillColor = .clear
        track.addChild(outerShape)

        let road = CGMutablePath()
        road.addEllipse(in: CGRect(
            x: trackCenter.x - trackRadiusX,
            y: trackCenter.y - trackRadiusY,
            width: trackRadiusX * 2,
            height: trackRadiusY * 2
        ))

        let roadShape = SKShapeNode(path: road)
        roadShape.strokeColor = UIColor(
            red: 0.22,
            green: 0.24,
            blue: 0.27,
            alpha: 1
        )
        roadShape.lineWidth = 55
        roadShape.fillColor = .clear
        track.addChild(roadShape)

        let inner = CGMutablePath()
        inner.addEllipse(in: CGRect(
            x: trackCenter.x - trackRadiusX + 28,
            y: trackCenter.y - trackRadiusY + 28,
            width: (trackRadiusX - 28) * 2,
            height: (trackRadiusY - 28) * 2
        ))

        let innerShape = SKShapeNode(path: inner)
        innerShape.strokeColor = UIColor(white: 0.12, alpha: 1)
        innerShape.lineWidth = 3
        innerShape.fillColor = UIColor(
            red: 0.12,
            green: 0.42,
            blue: 0.22,
            alpha: 1
        )
        track.addChild(innerShape)

        let startLine = SKShapeNode(
            rectOf: CGSize(width: 5, height: 50)
        )
        startLine.fillColor = .white
        startLine.strokeColor = .clear
        startLine.position = CGPoint(
            x: trackCenter.x,
            y: trackCenter.y - trackRadiusY
        )
        track.addChild(startLine)

        addChild(track)
    }

    private func addHUD() {
        let lap = makeLabel(
            text: "LAP 0 / 3",
            size: 15,
            color: .white
        )

        lap.horizontalAlignmentMode = .left
        lap.position = CGPoint(
            x: 20,
            y: size.height - 30
        )
        lap.name = "hud"
        lapLabel = lap
        addChild(lap)

        let speed = makeLabel(
            text: "SPEED 0",
            size: 13,
            color: .white
        )

        speed.horizontalAlignmentMode = .right
        speed.position = CGPoint(
            x: size.width - 20,
            y: size.height - 30
        )
        speed.name = "hud"
        speedLabel = speed
        addChild(speed)

        let back = makeLabel(
            text: "MENU",
            size: 12,
            color: .white
        )

        back.name = "back"
        back.position = CGPoint(
            x: size.width / 2,
            y: size.height - 30
        )
        back.name = "back"
        addChild(back)
    }

    private func addControls() {
        let left = addControl(
            name: "left",
            title: "◀",
            position: CGPoint(x: size.width * 0.12, y: size.height * 0.19)
        )

        let right = addControl(
            name: "right",
            title: "▶",
            position: CGPoint(x: size.width * 0.27, y: size.height * 0.19)
        )

        let gas = addControl(
            name: "gas",
            title: "GAS",
            position: CGPoint(x: size.width * 0.86, y: size.height * 0.2)
        )

        let brake = addControl(
            name: "brake",
            title: "BRAKE",
            position: CGPoint(x: size.width * 0.72, y: size.height * 0.13)
        )

        controlNodes = [left, right, gas, brake]
    }

    @discardableResult
    private func addControl(
        name: String,
        title: String,
        position: CGPoint
    ) -> SKNode {
        let width = min(size.width * 0.12, 85)
        let height = min(size.height * 0.22, 65)

        let button = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: 13
        )

        button.name = name
        button.position = position
        button.fillColor = UIColor(white: 1, alpha: 0.18)
        button.strokeColor = UIColor(white: 1, alpha: 0.35)
        button.lineWidth = 1
        button.zPosition = 20
        addChild(button)

        let label = makeLabel(
            text: title,
            size: 16,
            color: .white
        )

        label.name = name
        label.position = position
        label.zPosition = 21
        addChild(label)

        return button
    }

    // MARK: - Bots

    private func addBotCars() {
        let colors: [UIColor] = [
            .systemRed,
            .systemYellow
        ]

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

            let action = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(
                        x: 0,
                        y: trackRadiusY * 1.6,
                        duration: 3.5 + Double(index)
                    ),
                    SKAction.moveBy(
                        x: -offset * 2,
                        y: 0,
                        duration: 2
                    ),
                    SKAction.moveBy(
                        x: 0,
                        y: -trackRadiusY * 1.6,
                        duration: 3.5 + Double(index)
                    ),
                    SKAction.moveBy(
                        x: offset * 2,
                        y: 0,
                        duration: 2
                    )
                ])
            )

            bot.run(action)
        }
    }

    // MARK: - Touch controls

    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        for touch in touches {
            let location = touch.location(in: self)
            let nodes = nodes(at: location)

            for node in nodes {
                guard let name = node.name else {
                    continue
                }

                if mode == .menu {
                    switch name {
                    case "offline":
                        startGame(online: false)

                    case "host":
                        startGame(online: true)
                        multiplayer.startHosting()
                        statusLabel?.text = "Waiting for players..."

                    case "join":
                        startGame(online: true)
                        multiplayer.startJoining()
                        statusLabel?.text = "Searching for games..."

                    default:
                        break
                    }
                } else {
                    switch name {
                    case "left":
                        steering = 1

                    case "right":
                        steering = -1

                    case "gas":
                        throttle = 1

                    case "brake":
                        throttle = -0.6

                    case "back":
                        showMenu()

                    default:
                        break
                    }
                }
            }
        }
    }

    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        steering = 0
        throttle = 0
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        steering = 0
        throttle = 0
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard mode != .menu, raceStarted else {
            return
        }

        var deltaTime = currentTime - lastUpdate
        lastUpdate = currentTime

        if deltaTime <= 0 {
            return
        }

        deltaTime = min(deltaTime, 1.0 / 30.0)

        updatePlayer(deltaTime: CGFloat(deltaTime))

        if mode == .online {
            if currentTime - lastNetworkUpdate > 0.08 {
                multiplayer.sendPosition(
                    x: carPosition.x,
                    y: carPosition.y,
                    angle: carAngle
                )

                lastNetworkUpdate = currentTime
            }
        }

        updateHUD()
        updateLaps()
    }

    private func updatePlayer(deltaTime: CGFloat) {
        let speed = sqrt(
            carVelocity.dx * carVelocity.dx +
            carVelocity.dy * carVelocity.dy
        )

        if speed > 8 {
            carAngle += steering * deltaTime * min(speed / 45, 2.4)
        }

        let acceleration: CGFloat = 190

        carVelocity.dx += cos(carAngle) * throttle * acceleration * deltaTime
        carVelocity.dy += sin(carAngle) * throttle * acceleration * deltaTime

        let drag: CGFloat = throttle == 0 ? 0.985 : 0.996

        carVelocity.dx *= drag
        carVelocity.dy *= drag

        let maxSpeed: CGFloat = 260
        let currentSpeed = sqrt(
            carVelocity.dx * carVelocity.dx +
            carVelocity.dy * carVelocity.dy
        )

        if currentSpeed > maxSpeed {
            let factor = maxSpeed / currentSpeed
            carVelocity.dx *= factor
            carVelocity.dy *= factor
        }

        carPosition.x += carVelocity.dx * deltaTime
        carPosition.y += carVelocity.dy * deltaTime

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

    private func updateHUD() {
        let speed = Int(
            sqrt(
                carVelocity.dx * carVelocity.dx +
                carVelocity.dy * carVelocity.dy
            ) / 2
        )

        speedLabel?.text = "SPEED \(speed)"
        lapLabel?.text = "LAP \(lapCount) / 3"
    }

    private func updateLaps() {
        let checkpointY = trackCenter.y + trackRadiusY - 15

        if carPosition.y > checkpointY &&
            lastCheckpointY <= checkpointY &&
            carPosition.x > trackCenter.x - 45 &&
            carPosition.x < trackCenter.x + 45 {

            lapCount += 1

            if lapCount >= 3 {
                finishRace()
            }
        }

        lastCheckpointY = carPosition.y
    }

    private func finishRace() {
        raceStarted = false
        carVelocity = .zero

        let result = makeLabel(
            text: "YOU FINISHED!",
            size: min(size.width * 0.07, 38),
            color: .systemYellow
        )

        result.position = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )

        result.zPosition = 100
        addChild(result)

        let menu = makeLabel(
            text: "TAP MENU TO RETURN",
            size: 14,
            color: .white
        )

        menu.position = CGPoint(
            x: size.width / 2,
            y: size.height / 2 - 45
        )

        menu.zPosition = 100
        addChild(menu)

        let back = makeLabel(
            text: "MENU",
            size: 12,
            color: .white
        )

        back.name = "back"
        back.position = CGPoint(
            x: size.width / 2,
            y: size.height - 30
        )

        addChild(back)
    }

    // MARK: - Multiplayer callbacks

    func multiplayerPeerChanged() {
        let count = multiplayer.connectedPlayers().count + 1

        statusLabel?.text = "\(count) PLAYER(S) CONNECTED"

        for (index, name) in multiplayer.connectedPlayers().enumerated() {
            if remoteCars[name] == nil {
                let colors: [UIColor] = [
                    .systemRed,
                    .systemYellow,
                    .systemPurple
                ]

                let car = RacingCar(
                    color: colors[index % colors.count]
                )

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
        guard mode == .online else {
            return
        }

        if remoteCars[player] == nil {
            let car = RacingCar(color: .systemRed)
            remoteCars[player] = car
            addChild(car)
        }

        remoteCars[player]?.position = CGPoint(x: x, y: y)
        remoteCars[player]?.zRotation = angle
    }

    // MARK: - Helpers

    private func makeLabel(
        text: String,
        size: CGFloat,
        color: UIColor
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}