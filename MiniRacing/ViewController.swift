import UIKit
import SpriteKit

class ViewController: UIViewController {

    private var gameView: SKView!

    override func loadView() {
        gameView = SKView(frame: UIScreen.main.bounds)
        gameView.ignoresSiblingOrder = true
        gameView.isMultipleTouchEnabled = true
        view = gameView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let scene = GameScene(size: gameView.bounds.size)
        scene.scaleMode = .resizeFill
        gameView.presentScene(scene)

        gameView.preferredFramesPerSecond = 60
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
}