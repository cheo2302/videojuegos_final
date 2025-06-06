import UIKit
import QuartzCore
import SceneKit
import SpriteKit
import CoreMotion
import GameKit

public enum GameState {
    case title
    case introduction
    case playing
    case gameOver
}

class GameViewController: UIViewController, SCNSceneRendererDelegate, SCNPhysicsContactDelegate, GKGameCenterControllerDelegate {

    var gameState: GameState = .title
    var vidaMaxima: Int = 100
    var vidaActual: Int = 100
    var barraVida: SKShapeNode?

    var scene : SCNScene?
    var limits : CGRect = CGRect.zero
    var motion : CMMotionManager = CMMotionManager()

    var hud : SKScene?
    var marcadorAsteroides : SKLabelNode?

    var titleGroup : SCNNode?
    var gameOverGroup : SCNNode?
    var gameOverResultsText : SCNText?
    var gameOverResultsNode: SCNNode?
    var cameraNode : SCNNode?
    var cameraEulerAngle : SCNVector3?

    let categoryMaskShip = 0b001
    let categoryMaskShot = 0b010
    let categoryMaskAsteroid = 0b100

    var ship : SCNNode?
    var asteroidModel : SCNNode?
    var explosion : SCNParticleSystem?

    var soundExplosion : SCNAudioSource?

    var numAsteroides : Int = 0
    var velocity : Float = 0.0

    let spawnInterval : Float = 0.25
    var timeToSpawn : TimeInterval = 1.0
    var previousUpdateTime : TimeInterval?

    var gameOverOverlay: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()

        let scnView = self.view as! SCNView
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        self.scene = scene

        if let camNode = scene.rootNode.childNode(withName: "camera", recursively: true) {
            self.cameraNode = camNode
            self.cameraEulerAngle = camNode.eulerAngles
        }

        if let shipNode = scene.rootNode.childNode(withName: "ship", recursively: true) {
            self.ship = shipNode
            let shape = SCNPhysicsShape(geometry: SCNSphere(radius: 1.0), options: nil)
            let body = SCNPhysicsBody(type: .kinematic, shape: shape)
            body.categoryBitMask = categoryMaskShip
            body.contactTestBitMask = categoryMaskAsteroid
            body.collisionBitMask = 0
            shipNode.physicsBody = body
        }

        self.explosion = SCNParticleSystem(named: "Explode.scnp", inDirectory: "art.scnassets")

        if let existingTitle = scene.rootNode.childNode(withName: "titleGroup", recursively: true) {
            self.titleGroup = existingTitle
        } else {
            let titleNode = createTitleGroup()
            scene.rootNode.addChildNode(titleNode)
            self.titleGroup = titleNode
        }

        let gameOverNode = SCNNode()
        gameOverNode.name = "gameOverGroup"
        gameOverNode.position = SCNVector3(0, 0, -30)
        gameOverNode.isHidden = true

        let gameOverText = SCNText(string: "GAME OVER", extrusionDepth: 1.0)
        gameOverText.font = UIFont(name: "University", size: 12)
        gameOverText.firstMaterial?.diffuse.contents = UIColor.orange
        gameOverText.flatness = 0.1

        let gameOverTextNode = SCNNode(geometry: gameOverText)
        gameOverTextNode.scale = SCNVector3(0.5, 0.5, 0.5)
        let (minGO, maxGO) = gameOverText.boundingBox
        gameOverTextNode.pivot = SCNMatrix4MakeTranslation(minGO.x + (maxGO.x - minGO.x) / 2, minGO.y + (maxGO.y - minGO.y) / 2, 0)
        gameOverTextNode.position = SCNVector3(0, 3, 0)
        gameOverNode.addChildNode(gameOverTextNode)

        let resultsText = SCNText(string: "0 ASTEROIDS DESTROYED", extrusionDepth: 1.0)
        resultsText.font = UIFont(name: "University", size: 4)
        resultsText.firstMaterial?.diffuse.contents = UIColor.white
        resultsText.flatness = 0.1

        let resultsTextNode = SCNNode(geometry: resultsText)
        resultsTextNode.name = "gameOverResultsText"
        resultsTextNode.scale = SCNVector3(0.5, 0.5, 0.5)
        let (minRes, maxRes) = resultsText.boundingBox
        resultsTextNode.pivot = SCNMatrix4MakeTranslation(minRes.x + (maxRes.x - minRes.x) / 2, minRes.y + (maxRes.y - minRes.y) / 2, 0)
        resultsTextNode.position = SCNVector3(0, -2, 0)
        gameOverNode.addChildNode(resultsTextNode)

        scene.rootNode.addChildNode(gameOverNode)
        self.gameOverGroup = gameOverNode
        self.gameOverResultsNode = resultsTextNode
        self.gameOverResultsText = resultsText

        setupAsteroids(forView: scnView)
        setupAudio(inScene: scene)
        setupView(scnView, withScene: scene)
        startTapRecognition(inView: scnView)
        startMotionUpdates()
        scene.physicsWorld.contactDelegate = self
        showTitle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let scnView = self.view as! SCNView
        setupLimits(forView: scnView)
        setupHUD(inView: scnView)

        let player = GKLocalPlayer.local
        player.authenticateHandler = { (vc, error) in
            if let vc = vc {
                self.present(vc, animated: true, completion: nil)
            } else if player.isAuthenticated {
                print("✅ Game Center autenticado correctamente")
            } else if let error = error {
                print("❌ Error al autenticar Game Center: \(error.localizedDescription)")
            }
        }
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true, completion: nil)
    }

    func setupAudio(inScene scene: SCNScene) {
        if let musicaURL = Bundle.main.url(forResource: "rolemusic_step_to_space", withExtension: "mp3") {
            let musica = SCNAudioSource(url: musicaURL)!
            musica.loops = true
            musica.volume = 0.1
            musica.isPositional = false
            musica.load()
            let musicaAction = SCNAction.playAudio(musica, waitForCompletion: false)
            scene.rootNode.runAction(musicaAction)
        }

        if let bombURL = Bundle.main.url(forResource: "bomb", withExtension: "wav") {
            let bomb = SCNAudioSource(url: bombURL)!
            bomb.volume = 10.0
            bomb.isPositional = true
            bomb.load()
            self.soundExplosion = bomb
        }
    }

    func setupAsteroids(forView view: SCNView) {
        if let rockScene = SCNScene(named: "art.scnassets/rock.scn"),
           let asteroid = rockScene.rootNode.childNode(withName: "asteroid", recursively: true) {

            asteroid.scale = SCNVector3(1.0, 1.0, 1.0)

            let collider = SCNSphere(radius: 3.0)
            let shape = SCNPhysicsShape(geometry: collider, options: nil)

            let body = SCNPhysicsBody(type: .kinematic, shape: shape)
            body.categoryBitMask = categoryMaskAsteroid
            body.contactTestBitMask = categoryMaskShip | categoryMaskShot
            body.collisionBitMask = 0

            asteroid.physicsBody = body
            self.asteroidModel = asteroid
            view.prepare([asteroid], completionHandler: nil)
        }
    }

    func setupView(_ view: SCNView, withScene scene: SCNScene) {
        view.scene = scene
        view.allowsCameraControl = false
        view.showsStatistics = false
        view.backgroundColor = UIColor.black
        view.delegate = self
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
    }

    func setupLimits(forView view: SCNView) {
        let projectedOrigin = view.projectPoint(SCNVector3Zero)
        let unprojectedLeft = view.unprojectPoint(SCNVector3Make(0, projectedOrigin.y, projectedOrigin.z))
        let halfWidth = CGFloat(abs(unprojectedLeft.x))
        self.limits = CGRect(x: -halfWidth, y: -150, width: halfWidth * 2, height: 200)
    }

    func setupHUD(inView view: SCNView) {
        let overlayScene = SKScene(size: view.bounds.size)
        overlayScene.scaleMode = .resizeFill
        overlayScene.backgroundColor = .clear

        
        let label = SKLabelNode(fontNamed: "University")
        label.text = "0 HITS"
        label.fontSize = 30
        label.fontColor = UIColor.orange
        label.position = CGPoint(x: overlayScene.size.width - 120, y: overlayScene.size.height - 50)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        overlayScene.addChild(label)
        self.marcadorAsteroides = label

        
        let ancho: CGFloat = 150
        let alto: CGFloat = 20
        let barra = SKShapeNode(rectOf: CGSize(width: ancho, height: alto), cornerRadius: 5)
        barra.fillColor = .green
        barra.strokeColor = .white
        barra.lineWidth = 2
        barra.position = CGPoint(x: 110, y: overlayScene.size.height - 50)
        barra.name = "barraVida"
        overlayScene.addChild(barra)
        self.barraVida = barra

        view.overlaySKScene = overlayScene
        self.hud = overlayScene
    }

    func actualizarBarraVida() {
        let porcentaje = CGFloat(vidaActual) / CGFloat(vidaMaxima)
        barraVida?.xScale = porcentaje
        if porcentaje > 0.6 {
            barraVida?.fillColor = .green
        } else if porcentaje > 0.3 {
            barraVida?.fillColor = .orange
        } else {
            barraVida?.fillColor = .red
        }
    }


    func startTapRecognition(inView view: SCNView) {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }

    func startMotionUpdates() {
        if self.motion.isDeviceMotionAvailable {
            self.motion.deviceMotionUpdateInterval = 1.0 / 60.0
            self.motion.startDeviceMotionUpdates(to: OperationQueue.main) { (deviceMotion, error) in
                guard let attitude = deviceMotion?.attitude else { return }
                let roll = Float(attitude.roll)
                let pitch = Float(attitude.pitch)
                self.velocity = roll
                if let cameraNode = self.cameraNode,
                   let euler = self.cameraEulerAngle {
                    cameraNode.eulerAngles.z = euler.z - roll * 0.1
                    cameraNode.eulerAngles.x = euler.x - (pitch - 0.75) * 0.1
                }
            }
        }
    }

    func showTitle() {
        gameState = .title
        hud?.isHidden = true
        ship?.isHidden = true
        gameOverGroup?.isHidden = true
        gameOverOverlay?.removeFromSuperview()

        // Centra y muestra el grupo de título
        titleGroup?.isHidden = false
        titleGroup?.opacity = 1.0
        titleGroup?.position = SCNVector3(0, 0, -30)

        // Reinicia el texto parpadeante por si se detuvo
        if let tapNode = titleGroup?.childNode(withName: "tapToStart", recursively: true) {
            tapNode.removeAllActions()
            let fadeOut = SCNAction.fadeOpacity(to: 0.2, duration: 0.8)
            let fadeIn = SCNAction.fadeOpacity(to: 1.0, duration: 0.8)
            tapNode.runAction(SCNAction.repeatForever(SCNAction.sequence([fadeOut, fadeIn])))
        }
    }

    func createTitleGroup() -> SCNNode {
            let group = SCNNode()
            group.name = "titleGroup"

            // Texto principal 3D
            let titleText = SCNText(string: "SPACE\nMASTER\n2025", extrusionDepth: 4.0)
            titleText.font = UIFont(name: "University", size: 12)
            titleText.firstMaterial?.diffuse.contents = UIColor.orange
            titleText.firstMaterial?.specular.contents = UIColor.white
            titleText.firstMaterial?.emission.contents = UIColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1.0)
            titleText.firstMaterial?.shininess = 1.0
            titleText.flatness = 0.05
            titleText.alignmentMode = CATextLayerAlignmentMode.center.rawValue
            titleText.truncationMode = CATextLayerTruncationMode.none.rawValue
            titleText.isWrapped = true

            let titleNode = SCNNode(geometry: titleText)
            titleNode.name = "titleMain"
            titleNode.scale = SCNVector3(0.6, 0.6, 0.6)

            let (min, max) = titleText.boundingBox
            let dx = max.x - min.x
            let dy = max.y - min.y
            titleNode.pivot = SCNMatrix4MakeTranslation(min.x + dx / 2, min.y + dy / 2, 0)
            titleNode.position = SCNVector3(0, 10, 0)

            // Texto "TAP TO START"
            let tapText = SCNText(string: "TAP TO START", extrusionDepth: 2.0)
            tapText.font = UIFont(name: "University", size: 8)
            tapText.firstMaterial?.diffuse.contents = UIColor.white
            tapText.firstMaterial?.emission.contents = UIColor.white
            tapText.firstMaterial?.specular.contents = UIColor.gray
            tapText.firstMaterial?.shininess = 0.5
            tapText.flatness = 0.1
            tapText.alignmentMode = CATextLayerAlignmentMode.center.rawValue

            let tapNode = SCNNode(geometry: tapText)
            tapNode.name = "tapToStart"
            tapNode.scale = SCNVector3(0.5, 0.5, 0.5)

            let (minTap, maxTap) = tapText.boundingBox
            let dw = maxTap.x - minTap.x
            let dh = maxTap.y - minTap.y
            tapNode.pivot = SCNMatrix4MakeTranslation(minTap.x + dw / 2, minTap.y + dh / 2, 0)
            tapNode.position = SCNVector3(0, -20, 0)

            // Parpadeo en "TAP TO START"
            let fadeOut = SCNAction.fadeOpacity(to: 0.2, duration: 0.8)
            let fadeIn = SCNAction.fadeOpacity(to: 1.0, duration: 0.8)
            tapNode.runAction(SCNAction.repeatForever(SCNAction.sequence([fadeOut, fadeIn])))

            // Asegura que mire a la cámara
            let constraint = SCNBillboardConstraint()
            constraint.freeAxes = .all
            group.constraints = [constraint]

            group.addChildNode(titleNode)
            group.addChildNode(tapNode)
            group.position = SCNVector3(0, 0, -30)

            return group
        }

    func showGameOver() {
        gameState = .gameOver
        hud?.isHidden = true
        gameOverGroup?.isHidden = false

        let mensaje = "\(numAsteroides) ASTEROIDS DESTROYED"
        print("🎯 Mostrando: \(mensaje)")

        
        let updatedText = SCNText(string: mensaje, extrusionDepth: 1.0)
        updatedText.font = UIFont(name: "University", size: 4)
        updatedText.firstMaterial?.diffuse.contents = UIColor.white
        updatedText.flatness = 0.1

        
        gameOverResultsNode?.geometry = updatedText

        
        if let textNode = gameOverResultsNode, let newText = textNode.geometry as? SCNText {
            let (min, max) = newText.boundingBox
            let dx = max.x - min.x
            let dy = max.y - min.y
            textNode.pivot = SCNMatrix4MakeTranslation(min.x + dx / 2, min.y + dy / 2, 0)
            textNode.position = SCNVector3(0, -2, 0)
        }

        gameOverGroup?.position = SCNVector3(0, 0, -30)
        gameOverGroup?.opacity = 1.0
        gameOverGroup?.isHidden = false

        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .all
        gameOverGroup?.constraints = [constraint]
        
        let scoreReporter = GKScore(leaderboardIdentifier: "es.ua.mastermoviles.jtm.SpaceMaster")
        scoreReporter.value = Int64(self.numAsteroides)
        GKScore.report([scoreReporter]) { error in
            if let error = error {
                print("Error al reportar puntuación: \(error.localizedDescription)")
            } else {
                print("✅ Puntuación reportada correctamente.")
            }
        }
        if self.numAsteroides == 0 {
            let achievement = GKAchievement(identifier: "es.ua.mastermoviles.jtm.SpaceMaster.Achievement.WorstPlayer")
            achievement.showsCompletionBanner = true
            achievement.percentComplete = 100
            GKAchievement.report([achievement], withCompletionHandler: nil)
        }
        if self.numAsteroides >= 1 {
            let achievement = GKAchievement(identifier: "es.ua.mastermoviles.jtm.SpaceMaster.Achievement.FirstHit")
            achievement.showsCompletionBanner = true
            achievement.percentComplete = 100
            GKAchievement.report([achievement], withCompletionHandler: nil)
        }
        if self.numAsteroides >= 20 {
            let achievement = GKAchievement(identifier: "es.ua.mastermoviles.jtm.SpaceMaster.Achievement.Asteroid20")
            achievement.showsCompletionBanner = true
            achievement.percentComplete = 100
            GKAchievement.report([achievement], withCompletionHandler: nil)
        }
    }


    func startGame() {
        vidaActual = vidaMaxima
        actualizarBarraVida()
        gameState = .introduction
        titleGroup?.isHidden = true
        hud?.isHidden = false
        ship?.isHidden = false
        marcadorAsteroides?.text = ""
        ship?.position = SCNVector3(0, 50, 50)
        let mover = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 1.0)
        let finalizar = SCNAction.run { _ in self.gameState = .playing }
        let secuencia = SCNAction.sequence([mover, finalizar])
        ship?.runAction(secuencia)
    }


    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let deltaTime = time - (previousUpdateTime ?? time)
        previousUpdateTime = time
        guard gameState == .playing else { return }
        timeToSpawn -= deltaTime
        if timeToSpawn <= 0 {
            timeToSpawn = TimeInterval(spawnInterval)
            let randomX = Float.random(in: Float(limits.minX)...Float(limits.maxX))
            let spawnPosition = SCNVector3(randomX, 0, Float(limits.minY))
            spawnAsteroid(pos: spawnPosition)
        }

        if let ship = self.ship {
            let desplazamiento = velocity * 200 * Float(deltaTime)
            var nuevaX = ship.position.x + desplazamiento
            let limiteX = Float(limits.width / 2) - 2
            nuevaX = max(-limiteX, min(limiteX, nuevaX))
            ship.position.x = nuevaX
            ship.eulerAngles.z = -velocity * 0.5
        }
    }

    func spawnAsteroid(pos: SCNVector3) {
        guard let model = self.asteroidModel else { return }
        let asteroid = model.clone()
        asteroid.name = "asteroid"

        let spawnZ: Float = -100
        let destinoZ: Float = 50
        asteroid.position = SCNVector3(pos.x, 0, spawnZ)

        let mover = SCNAction.move(to: SCNVector3(pos.x, 0, destinoZ), duration: 3.0)
        let eje = SCNVector3(x: Float.random(in: -1...1), y: Float.random(in: -1...1), z: Float.random(in: -1...1))
        let rotar = SCNAction.rotate(by: 10, around: eje, duration: 3.0)
        let eliminar = SCNAction.removeFromParentNode()
        let acciones = SCNAction.group([mover, rotar])
        let secuencia = SCNAction.sequence([acciones, eliminar])
        asteroid.runAction(secuencia)

        let shape = SCNPhysicsShape(geometry: SCNSphere(radius: 1.0), options: nil)
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.categoryBitMask = categoryMaskAsteroid
        body.contactTestBitMask = categoryMaskShip | categoryMaskShot
        body.collisionBitMask = 0
        asteroid.physicsBody = body

        self.scene?.rootNode.addChildNode(asteroid)
    }

    func shot() {
        guard gameState == .playing else { return }
        let esfera = SCNSphere(radius: 1.0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1.0)
        material.emission.contents = UIColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1.0)
        esfera.firstMaterial = material

        let bala = SCNNode(geometry: esfera)
        bala.name = "bullet"
        if let ship = self.ship {
            bala.position = ship.position
            scene?.rootNode.addChildNode(bala)
            let mover = SCNAction.moveBy(x: 0, y: 0, z: -150, duration: 1.0)
            let eliminar = SCNAction.removeFromParentNode()
            let secuencia = SCNAction.sequence([mover, eliminar])
            bala.runAction(secuencia)
            let cuerpo = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: esfera, options: nil))
            cuerpo.categoryBitMask = categoryMaskShot
            cuerpo.contactTestBitMask = categoryMaskAsteroid
            cuerpo.collisionBitMask = 0
            bala.physicsBody = cuerpo
        }
    }

    func createShotNode() -> SCNNode {
        let geometry = SCNSphere(radius: 0.3)
        geometry.firstMaterial?.diffuse.contents = UIColor.cyan

        let node = SCNNode(geometry: geometry)
        node.position = ship?.presentation.position ?? SCNVector3Zero

        let shape = SCNPhysicsShape(geometry: geometry, options: nil)
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.isAffectedByGravity = false
        body.categoryBitMask = categoryMaskShot
        body.contactTestBitMask = categoryMaskAsteroid
        body.collisionBitMask = 0

        node.physicsBody = body

        return node
    }

    
    func destroyAsteroid(asteroid: SCNNode, withBullet bullet: SCNNode) {
        showExplosion(onNode: asteroid)
        asteroid.removeFromParentNode()
        bullet.removeFromParentNode()
        numAsteroides += 1
        print("✅ Asteroide destruido. Total: \(numAsteroides)")
        marcadorAsteroides?.text = "\(numAsteroides) HITS"
    }

    func destroyShip(ship: SCNNode, withAsteroid asteroid: SCNNode) {
        asteroid.removeFromParentNode()

        if let impact = SCNParticleSystem(named: "Explode2.scnp", inDirectory: "art.scnassets") {
            let impactoNode = SCNNode()
            impactoNode.position = asteroid.presentation.position
            impactoNode.addParticleSystem(impact)
            self.scene?.rootNode.addChildNode(impactoNode)

            if let sonido = soundExplosion {
                let sonidoAction = SCNAction.playAudio(sonido, waitForCompletion: false)
                impactoNode.runAction(sonidoAction)
            }

            let delay = SCNAction.wait(duration: 2.0)
            let remove = SCNAction.removeFromParentNode()
            impactoNode.runAction(SCNAction.sequence([delay, remove]))
        }

        vidaActual -= 25
        actualizarBarraVida()

        let shape = SCNPhysicsShape(geometry: SCNSphere(radius: 2.0), options: nil)
        ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape)
        ship.physicsBody?.categoryBitMask = categoryMaskShip
        ship.physicsBody?.contactTestBitMask = categoryMaskAsteroid
        ship.physicsBody?.collisionBitMask = 0

        if vidaActual <= 0 {
            if let explosion = self.explosion {
                let explosionNode = SCNNode()
                explosionNode.position = ship.presentation.position
                explosionNode.addParticleSystem(explosion)
                self.scene?.rootNode.addChildNode(explosionNode)

                if let sonido = soundExplosion {
                    let sonidoAction = SCNAction.playAudio(sonido, waitForCompletion: false)
                    explosionNode.runAction(sonidoAction)
                }

                let delay = SCNAction.wait(duration: 2.0)
                let remove = SCNAction.removeFromParentNode()
                explosionNode.runAction(SCNAction.sequence([delay, remove]))
            }

            let desaparecer = SCNAction.sequence([
                SCNAction.fadeOut(duration: 0.3),
                SCNAction.removeFromParentNode()
            ])
            ship.runAction(desaparecer)

            let delay = SCNAction.wait(duration: 2.0)
            let finalizar = SCNAction.run { [weak self] _ in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    self.showGameOver()

                    self.gameOverOverlay?.removeFromSuperview()

                    let overlay = UIView(frame: self.view.bounds)
                    overlay.backgroundColor = UIColor.clear
                    overlay.isUserInteractionEnabled = true
                    self.view.addSubview(overlay)
                    self.gameOverOverlay = overlay

                    let volverButton = UIButton(type: .system)
                    volverButton.setTitle("Volver al Título", for: .normal)
                    volverButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
                    volverButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                    volverButton.setTitleColor(.white, for: .normal)
                    volverButton.layer.cornerRadius = 10
                    volverButton.frame = CGRect(x: overlay.bounds.midX - 100, y: overlay.bounds.midY + 60, width: 200, height: 50)
                    volverButton.addTarget(self, action: #selector(self.volverAlTitulo), for: .touchUpInside)
                    overlay.addSubview(volverButton)

                    let reiniciarButton = UIButton(type: .system)
                    reiniciarButton.setTitle("Reiniciar Partida", for: .normal)
                    reiniciarButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
                    reiniciarButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                    reiniciarButton.setTitleColor(.white, for: .normal)
                    reiniciarButton.layer.cornerRadius = 10
                    reiniciarButton.frame = CGRect(x: overlay.bounds.midX - 100, y: overlay.bounds.midY + 120, width: 200, height: 50)
                    reiniciarButton.addTarget(self, action: #selector(self.reiniciarPartida), for: .touchUpInside)
                    overlay.addSubview(reiniciarButton)

                    let gameCenterButton = UIButton(type: .system)
                    gameCenterButton.setTitle("Ver Game Center", for: .normal)
                    gameCenterButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
                    gameCenterButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                    gameCenterButton.setTitleColor(.white, for: .normal)
                    gameCenterButton.layer.cornerRadius = 10
                    gameCenterButton.frame = CGRect(x: overlay.bounds.midX - 100, y: overlay.bounds.midY + 180, width: 200, height: 50)
                    gameCenterButton.addTarget(self, action: #selector(self.mostrarPanelGameCenter), for: .touchUpInside)
                    overlay.addSubview(gameCenterButton)
                }
            }
            self.scene?.rootNode.runAction(SCNAction.sequence([delay, finalizar]))
        }
    }


    @objc func mostrarPanelGameCenter() {
        let player = GKLocalPlayer.local

        if player.isAuthenticated {
            let controller = GKGameCenterViewController()
            controller.gameCenterDelegate = self
            self.present(controller, animated: true, completion: nil)
        } else {
            player.authenticateHandler = { (vc, error) in
                if let vc = vc {
                    self.present(vc, animated: true, completion: nil)
                } else if player.isAuthenticated {
                    print("✅ Game Center autenticado")
                } else if let error = error {
                    print("❌ Error Game Center: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func volverAlTitulo() {
        gameOverOverlay?.removeFromSuperview()
        
        scene?.rootNode.enumerateChildNodes { node, _ in
            if node.name == "asteroid" || node.name == "bullet" {
                node.removeFromParentNode()
            }
        }

        if let ship = self.ship {
            ship.isHidden = false
            ship.opacity = 1.0
            ship.removeAllActions()
            ship.position = SCNVector3(0, 50, 50)
            scene?.rootNode.addChildNode(ship)
        }

        numAsteroides = 0
        marcadorAsteroides?.text = "0 HITS"

        showTitle()
    }

    @objc func reiniciarPartida() {
        gameOverOverlay?.removeFromSuperview()
        gameOverGroup?.isHidden = true

        scene?.rootNode.enumerateChildNodes { node, _ in
            if node.name == "asteroid" || node.name == "bullet" {
                node.removeFromParentNode()
            }
        }

        if let ship = self.ship {
            ship.isHidden = false
            ship.opacity = 1.0
            ship.removeAllActions()
            ship.position = SCNVector3(0, 50, 50)
            scene?.rootNode.addChildNode(ship)
        }

        startGame()
    }

    func showExplosion(onNode node: SCNNode) {
        guard let explosion = self.explosion else {
            print("🚫 No se encontró el sistema de partículas 'Explode.scnp'")
            return
        }

        let particleNode = SCNNode()
        particleNode.addParticleSystem(explosion)
        particleNode.position = node.presentation.position
        self.scene?.rootNode.addChildNode(particleNode)

        if let sonido = soundExplosion {
            let sonidoAction = SCNAction.playAudio(sonido, waitForCompletion: false)
            particleNode.runAction(sonidoAction)
        }
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        guard let a = contact.nodeA.name, let b = contact.nodeB.name else { return }
        if a == "bullet" && b == "asteroid" {
            destroyAsteroid(asteroid: contact.nodeB, withBullet: contact.nodeA)
        } else if a == "asteroid" && b == "bullet" {
            destroyAsteroid(asteroid: contact.nodeA, withBullet: contact.nodeB)
        } else if a == "ship" && b == "asteroid" {
            destroyShip(ship: contact.nodeA, withAsteroid: contact.nodeB)
        } else if a == "asteroid" && b == "ship" {
            destroyShip(ship: contact.nodeB, withAsteroid: contact.nodeA)
        }
    }

    @objc func handleTap(_ gestureRecognize: UIGestureRecognizer) {
            switch gameState {
            case .title:
                startGame()
            case .playing:
                shot()
            default:
                break
            }
        }

        override var shouldAutorotate: Bool { return true }
        override var prefersStatusBarHidden: Bool { return true }
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
        }
    }

    extension SCNVector3 {
        static func * (vector: SCNVector3, scalar: Float) -> SCNVector3 {
            return SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
        }

        static func * (vector: SCNVector3, scalar: Double) -> SCNVector3 {
            return vector * Float(scalar)
        }
    }
