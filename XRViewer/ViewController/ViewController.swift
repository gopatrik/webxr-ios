import UIKit
import GCDWebServer
import CoreLocation
import CocoaLumberjack

let UNSUPPORTED_CONFIGURATION_ARKIT_ERROR_MESSAGE = "The selected ARSessionConfiguration is not supported by the current device"
let SENSOR_UNAVAILABLE_ARKIT_ERROR_MESSAGE = "A sensor required to run the session is not available"
let SENSOR_FAILED_ARKIT_ERROR_MESSAGE = "A sensor failed to provide the required input.\nWe will try to restart the session using a Gravity World Alignment"
let WORLD_TRACKING_FAILED_ARKIT_ERROR_MESSAGE = "World tracking has encountered a fatal error"

let AR_SESSION_STARTED_POPUP_TITLE = "AR Session Started"
let AR_SESSION_STARTED_POPUP_MESSAGE = "Swipe down to show the URL bar"
let AR_SESSION_STARTED_POPUP_TIME_IN_SECONDS = 2

let MEMORY_ERROR_DOMAIN = "Memory"
let MEMORY_ERROR_CODE = 0
let MEMORY_ERROR_MESSAGE = "Memory warning received"


/**
 The main view controller of the app. It's the holder of the other controllers.
 It listens to events happening on the controllers and passes them to the ones
 interested on them.
 */
#if WEBSERVER
#endif

let WAITING_TIME_ON_MEMORY_WARNING = 0.5
typealias UICompletion = () -> Void

class ViewController: UIViewController, UIGestureRecognizerDelegate, GCDWebServerDelegate {
#if WEBSERVER
    private var webServer: GCDWebServer?

#endif
    @IBOutlet private weak var splashLayerView: LayerView!
    @IBOutlet private weak var arkLayerView: LayerView!
    @IBOutlet private weak var hotLayerView: LayerView!
    @IBOutlet private weak var webLayerView: LayerView!
    private var stateController: AppStateController?
    var arkController: ARKController?
    var webController: WebController?
    var overlayController: UIOverlayController?
    private var locationManager: LocationManager?
    var messageController: MessageController?
    private var animator: Animator?
    private var reachability: Reachability?
    private var timerSessionRunningInBackground: Timer?
    
    let session = ARSession()
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var messagePanel: UIVisualEffectView!
    @IBOutlet weak var messageLabel: UILabel!
    var textManager: TextManager!
    
    // MARK: - View Lifecycle
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        /// This causes UIKit to call preferredScreenEdgesDeferringSystemGestures,
        /// so we can say what edges we want our gestures to take precedence over the system gestures
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()

        setupCommonControllers()
        setupUI()
        setupScene()

        /// Apparently, this is called async in the main queue because we need viewDidLoad to finish
        /// its execution before doing anything on the subviews. This also could have been called from
        /// viewDidAppear
        DispatchQueue.main.async(execute: {
            self.setupTargetControllers()
        })


        /// Swipe from edge gesture recognizer setup
        let gestureRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(ViewController.swipe(fromEdge:)))
        gestureRecognizer.edges = .top
        gestureRecognizer.delegate = self
        view.addGestureRecognizer(gestureRecognizer)

        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(ViewController.swipeUp(_:)))
        swipeGestureRecognizer.direction = .up
        swipeGestureRecognizer.delegate = self
        view.addGestureRecognizer(swipeGestureRecognizer)

        /// Show the permissions popup if we have never shown it
        if UserDefaults.standard.bool(forKey: Constant.permissionsUIAlreadyShownKey()) == false && (CLLocationManager.authorizationStatus() == .notDetermined || AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined) {
            DispatchQueue.main.async(execute: {
                UserDefaults.standard.set(true, forKey: Constant.permissionsUIAlreadyShownKey())
                self.messageController?.showPermissionsPopup()
            })
        }
    }

#if WEBSERVER
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        var options: [AnyHashable : Any] = [:]
        options[GCDWebServerOption_Port] = 8080
        //[options setObject:@NO forKey:GCDWebServerOption_AutomaticallySuspendInBackground];

        let documentsPath = URL(fileURLWithPath: Bundle.main.resourcePath ?? "").appendingPathComponent("Web").absoluteString

        if FileManager.default.fileExists(atPath: documentsPath) {
            webServer = GCDWebServer()
            webServer?.addGETHandler(forBasePath: "/", directoryPath: documentsPath, indexFilename: "index.html", cacheAge: 0, allowRangeRequests: true)

            webServer?.delegate = self
            if webServer?.start(withOptions: options, error: nil) != nil {
                print(String(format: "GCDWebServer running locally on port %i", Int(webServer?.port ?? 0)))
            } else {
                print("GCDWebServer not running!")
            }
        } else {
            print("No Web directory, GCDWebServer not running!")
        }
    }

#endif
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

#if WEBSERVER
        webServer?.stop()
        webServer = nil
#endif
    }

    @objc func swipe(fromEdge recognizer: UISwipeGestureRecognizer?) {
        guard let webXR = stateController?.state?.webXR else { return }
        guard let debugSelected = webController?.isDebugButtonSelected() else { return }
        if webXR {
            if debugSelected {
                stateController?.setShowMode(.multiDebug)
            } else {
                stateController?.setShowMode(.multi)
            }
        }
    }

    @objc func swipeUp(_ recognizer: UISwipeGestureRecognizer?) {
        guard let webXR = stateController?.state?.webXR else { return }
        guard let debugSelected = webController?.isDebugButtonSelected() else { return }
        let location: CGPoint? = recognizer?.location(in: view)
        if (location?.y ?? 0.0) > Constant.swipeGestureAreaHeight() {
            return
        }

        if webXR {
            if debugSelected {
                stateController?.setShowMode(.debug)
            } else {
                stateController?.setShowMode(.nothing)
            }
            webController?.hideKeyboard()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        DDLogError("didReceiveMemoryWarning")

        processMemoryWarning()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        guard let webXR = stateController?.state?.webXR else { return }
        // Disable the transition animation if we are on XR
        if webXR {
            coordinator.animate(alongsideTransition: nil) { context in
                UIView.setAnimationsEnabled(true)
            }
            UIView.setAnimationsEnabled(false)
        }

        arkController?.viewWillTransition(to: size)
        overlayController?.viewWillTransition(to: size)
        webController?.viewWillTransition(to: size)

        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateConstraints()
    }

    func updateConstraints() {
        guard let barViewHeight = webController?.barViewHeightAnchorConstraint else { return }
        guard let webViewTop = webController?.webViewTopAnchorConstraint else { return }
        guard let webViewLeft = webController?.webViewLeftAnchorConstraint else { return }
        guard let webViewRight = webController?.webViewRightAnchorConstraint else { return }
        guard let webXR = stateController?.state?.webXR else { return }
        // If XR is active, then the top anchor is 0 (fullscreen), else topSafeAreaInset + Constant.urlBarHeight()
        let topSafeAreaInset = UIApplication.shared.keyWindow?.safeAreaInsets.top ?? 0.0
        barViewHeight.constant = topSafeAreaInset + Constant.urlBarHeight()
        webViewTop.constant = webXR ? 0.0 : topSafeAreaInset + Constant.urlBarHeight()

        webViewLeft.constant = 0.0
        webViewRight.constant = 0.0
        if stateController?.state?.webXR == nil {
            let currentOrientation: UIInterfaceOrientation = Utils.getInterfaceOrientationFromDeviceOrientation()
            if currentOrientation == .landscapeLeft {
                // The notch is to the right
                let rightSafeAreaInset = UIApplication.shared.keyWindow?.safeAreaInsets.right ?? 0.0
                webViewRight.constant = webXR ? 0.0 : -rightSafeAreaInset
            } else if currentOrientation == .landscapeRight {
                // The notch is to the left
                let leftSafeAreaInset = CGFloat(UIApplication.shared.keyWindow?.safeAreaInsets.left ?? 0.0)
                webViewLeft.constant = leftSafeAreaInset
            }
        }

        webLayerView.setNeedsLayout()
        webLayerView.layoutIfNeeded()
    }

    override var prefersStatusBarHidden: Bool {
        return super.prefersStatusBarHidden
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return .top
    }

    // MARK: - Setup
    
    func setupScene() {
        // Set up the scene view
        sceneView.delegate = self
        guard let session = arkController?.session else { return }
        sceneView.session = session
    }
    
    func setupUI() {
        textManager = TextManager(viewController: self)
        
        // Set appearance of the message output panel
        messagePanel.layer.cornerRadius = 3.0
        messagePanel.clipsToBounds = true
        messagePanel.isHidden = true
        messageLabel.text = ""
    }
    
    func setupCommonControllers() {
        setupStateController()
        setupAnimator()
        setupMessageController()
        setupReachability()
        setupNotifications()
    }

    func setupStateController() {
        weak var blockSelf: ViewController? = self

        self.stateController = AppStateController(state: AppState.defaultState())

        stateController?.onDebug = { showDebug in
            blockSelf?.webController?.showDebug(showDebug)
        }

        stateController?.onModeUpdate = { mode in
            blockSelf?.arkController?.setShowMode(mode)
            blockSelf?.overlayController?.setMode(mode)
            guard let showURL = blockSelf?.stateController?.shouldShowURLBar() else { return }
            blockSelf?.webController?.showBar(showURL)
        }

        stateController?.onOptionsUpdate = { options in
            blockSelf?.arkController?.setShowOptions(options)
            blockSelf?.overlayController?.setOptions(options)
            guard let showURL = blockSelf?.stateController?.shouldShowURLBar() else { return }
            blockSelf?.webController?.showBar(showURL)
        }

        stateController?.onXRUpdate = { xr in
            if xr {
                guard let debugSelected = blockSelf?.webController?.isDebugButtonSelected() else { return }
                guard let shouldShowSessionStartedPopup = blockSelf?.stateController?.state?.shouldShowSessionStartedPopup else { return }
                
                if debugSelected {
                    blockSelf?.stateController?.setShowMode(.debug)
                } else {
                    blockSelf?.stateController?.setShowMode(.nothing)
                }

                if shouldShowSessionStartedPopup {
                    blockSelf?.stateController?.state?.shouldShowSessionStartedPopup = false
                    blockSelf?.messageController?.showMessage(withTitle: AR_SESSION_STARTED_POPUP_TITLE, message: AR_SESSION_STARTED_POPUP_MESSAGE, hideAfter: AR_SESSION_STARTED_POPUP_TIME_IN_SECONDS)
                }

                blockSelf?.webController?.lastXRVisitedURL = blockSelf?.webController?.webView?.url?.absoluteString ?? ""
            } else {
                blockSelf?.stateController?.setShowMode(.nothing)
                if blockSelf?.arkController?.arSessionState == .ARKSessionRunning {
                    blockSelf?.timerSessionRunningInBackground?.invalidate()
                    let timerSeconds: Int = UserDefaults.standard.integer(forKey: Constant.secondsInBackgroundKey())
                    print(String(format: "\n\n*********\n\nMoving away from an XR site, keep ARKit running, and launch the timer for %ld seconds\n\n*********", timerSeconds))
                    blockSelf?.timerSessionRunningInBackground = Timer.scheduledTimer(withTimeInterval: TimeInterval(timerSeconds), repeats: false, block: { timer in
                        print("\n\n*********\n\nTimer expired, pausing session\n\n*********")
                        UserDefaults.standard.set(Date(), forKey: "backgroundOrPausedDateKey")
                        blockSelf?.arkController?.pauseSession()
                        timer.invalidate()
                    })
                }
            }

            blockSelf?.updateConstraints()

            blockSelf?.webController?.setup(forWebXR: xr)
        }

        stateController?.onReachable = { url in
            blockSelf?.loadURL(url)
        }

        stateController?.onEnterForeground = { url in
            blockSelf?.stateController?.state?.shouldRemoveAnchorsOnNextARSession = false

            blockSelf?.messageController?.clean()
            let requestedURL = UserDefaults.standard.string(forKey: REQUESTED_URL_KEY)
            if requestedURL != nil {
                print("\n\n*********\n\nMoving to foreground because the user wants to open a URL externally, loading the page\n\n*********")
                UserDefaults.standard.set(nil, forKey: REQUESTED_URL_KEY)
                blockSelf?.loadURL(requestedURL)
            } else {
                guard let arSessionState = blockSelf?.arkController?.arSessionState else { return }
                switch arSessionState {
                    case .ARKSessionUnknown:
                        print("\n\n*********\n\nMoving to foreground while ARKit is not initialized, do nothing\n\n*********")
                    case .ARKSessionPaused:
                        guard let hasWorldMap = blockSelf?.arkController?.hasBackgroundWorldMap() else { return }
                        if !hasWorldMap {
                            // if no background map, then need to remove anchors on next session
                            print("\n\n*********\n\nMoving to foreground while the session is paused, remember to remove anchors on next AR request\n\n*********")
                            blockSelf?.stateController?.state?.shouldRemoveAnchorsOnNextARSession = true
                        }
                    case .ARKSessionRunning:
                        guard let hasWorldMap = blockSelf?.arkController?.hasBackgroundWorldMap() else { return }
                        if hasWorldMap {
                            print("\n\n*********\n\nMoving to foreground while the session is running and it was in BG and there is a saved WorldMap\n\n*********")

                            print("\n\n*********\n\nResume session, which will use the worldmap\n\n*********")
                            guard let state = blockSelf?.stateController?.state else { return }
                            blockSelf?.arkController?.resumeSession(fromBackground: state)
                        } else {
                            let interruptionDate = UserDefaults.standard.object(forKey: Constant.backgroundOrPausedDateKey()) as? Date
                            let now = Date()
                            if let aDate = interruptionDate {
                                if now.timeIntervalSince(aDate) >= Constant.pauseTimeInSecondsToRemoveAnchors() {
                                    print("\n\n*********\n\nMoving to foreground while the session is running and it was in BG for a long time, remove the anchors\n\n*********")
                                    blockSelf?.arkController?.removeAllAnchors()
                                } else {
                                    print("\n\n*********\n\nMoving to foreground while the session is running and it was in BG for a short time, do nothing\n\n*********")
                                }
                            }
                        }
                    default:
                        break
                }
            }

            UserDefaults.standard.set(nil, forKey: Constant.backgroundOrPausedDateKey())
        }

        stateController?.onMemoryWarning = { url in
            blockSelf?.messageController?.showMessageAboutMemoryWarning(withCompletion: {
                self.webController?.loadBlankHTMLString()
            })

            blockSelf?.webController?.didReceiveError(error: NSError(domain: MEMORY_ERROR_DOMAIN, code: MEMORY_ERROR_CODE, userInfo: [NSLocalizedDescriptionKey: MEMORY_ERROR_MESSAGE]))
        }

        stateController?.onRequestUpdate = { dict in
            print("\n\n*********\n\nInvalidate timer\n\n*********")
            blockSelf?.timerSessionRunningInBackground?.invalidate()

            if blockSelf?.arkController == nil {
                print("\n\n*********\n\nARKit is nil, instantiate and start a session\n\n*********")
                blockSelf?.startNewARKitSession(withRequest: dict)
                guard let session = blockSelf?.arkController?.session else { return }
                self.sceneView.session = session
            } else {
                guard let arSessionState = blockSelf?.arkController?.arSessionState else { return }
                guard let state = blockSelf?.stateController?.state else { return }
                switch arSessionState {
                    case .ARKSessionUnknown:
                        print("\n\n*********\n\nARKit is in unknown state, instantiate and start a session\n\n*********")
                        blockSelf?.arkController?.runSession(with: state)
                    case .ARKSessionRunning:
                        if blockSelf?.urlIsNotTheLastXRVisitedURL() ?? false {
                            print("\n\n*********\n\nThis site is not the last XR site visited, and the timer hasn't expired yet. Remove distant anchors and continue with the session\n\n*********")
                            blockSelf?.arkController?.removeDistantAnchors()
                            blockSelf?.arkController?.runSession(with: state)
                        } else {
                            print("\n\n*********\n\nThis site is the last XR site visited, and the timer hasn't expired yet. Continue with the session\n\n*********")
                        }
                    case .ARKSessionPaused:
                        print("\n\n*********\n\nRequest of a new AR session when it's paused\n\n*********")
                        guard let shouldRemoveAnchors = blockSelf?.stateController?.state?.shouldRemoveAnchorsOnNextARSession else { return }
                        if shouldRemoveAnchors {
                            print("\n\n*********\n\nRun session removing anchors\n\n*********")
                            blockSelf?.stateController?.state?.shouldRemoveAnchorsOnNextARSession = false
                            blockSelf?.arkController?.runSessionRemovingAnchors(with: state)
                        } else {
                            print("\n\n*********\n\nResume session\n\n*********")
                            blockSelf?.arkController?.resumeSession(with: state)
                        }
                    default:
                        break
                }
            }
            if (dict?[WEB_AR_CV_INFORMATION_OPTION] != nil) {
                blockSelf?.stateController?.state?.computerVisionFrameRequested = true
                blockSelf?.arkController?.computerVisionFrameRequested = true
                blockSelf?.stateController?.state?.sendComputerVisionData = true
            }
        }
    }

    func urlIsNotTheLastXRVisitedURL() -> Bool {
        return !(webController?.webView?.url?.absoluteString == webController?.lastXRVisitedURL)
    }

    func startNewARKitSession(withRequest request: [AnyHashable : Any]?) {
        setupLocationController()
        locationManager?.setup(forRequest: request)
        setupARKController()
    }

    func setupAnimator() {
        self.animator = Animator()
    }

    func setupMessageController() {
        self.messageController = MessageController(viewController: self)

        weak var blockSelf: ViewController? = self

        messageController?.didShowMessage = {
            blockSelf?.stateController?.saveOnMessageShowMode()
            blockSelf?.stateController?.setShowMode(.nothing)
        }

        messageController?.didHideMessage = {
            blockSelf?.stateController?.applyOnMessageShowMode()
        }

        messageController?.didHideMessageByUser = {
            //[[blockSelf stateController] applyOnMessageShowMode];
        }
    }

    func setupNotifications() {
        weak var blockSelf: ViewController? = self

        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: OperationQueue.main, using: { note in
            guard let arSessionState = blockSelf?.arkController?.arSessionState else { return }
            switch arSessionState {
                case .ARKSessionUnknown:
                    print("\n\n*********\n\nMoving to background while ARKit is not initialized, nothing to do\n\n*********")
                case .ARKSessionPaused:
                    print("\n\n*********\n\nMoving to background while the session is paused, nothing to do\n\n*********")
                    // need to try and save WorldMap here.  May fail?
                    self.arkController?.saveWorldMapInBackground()
                case .ARKSessionRunning:
                    print("\n\n*********\n\nMoving to background while the session is running, store the timestamp\n\n*********")
                    UserDefaults.standard.set(Date(), forKey: Constant.backgroundOrPausedDateKey())
                    // need to save WorldMap here
                    self.arkController?.saveWorldMapInBackground()
                default:
                    break
            }

            blockSelf?.webController?.didBackgroundAction(true)

            blockSelf?.stateController?.saveMoveToBackground(onURL: blockSelf?.webController?.lastURL)
        })

        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: OperationQueue.main, using: { note in
            blockSelf?.stateController?.applyOnEnterForegroundAction()
        })

        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.deviceOrientationDidChange(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc func deviceOrientationDidChange(_ notification: Notification?) {
        arkController?.shouldUpdateWindowSize = true
        updateConstraints()
    }

    func setupReachability() {
        self.reachability = Reachability()
        do {
            try reachability?.startNotifier()
        } catch {
            print("Error starting Reachability notifier!")
        }

        weak var blockSelf: ViewController? = self

        let ReachBlock: (() -> Void)? = {
            let netStatus = blockSelf?.reachability?.connection
                let isReachable: Bool = netStatus != .none
                DDLogDebug("Connection isReachable - \(isReachable)")

                if isReachable {
                    blockSelf?.stateController?.applyOnReachableAction()
                } else if isReachable == false && blockSelf?.webController?.lastURL == nil {
                    blockSelf?.messageController?.showMessageAboutConnectionRequired()
                    blockSelf?.stateController?.saveNotReachable(onURL: nil)
                }
            }

        NotificationCenter.default.addObserver(forName: NSNotification.Name.reachabilityChanged, object: nil, queue: OperationQueue.main, using: { note in
            ReachBlock?()
        })

        ReachBlock?()
    }

    func setupTargetControllers() {
        setupLocationController()

        setupWebController()

        setupOverlayController()
    }

    func setupLocationController() {
        self.locationManager = LocationManager()
        locationManager?.setup(forRequest: stateController?.state?.aRRequest)
    }

    func setupARKController() {
        CLEAN_VIEW(v: arkLayerView)

        weak var blockSelf: ViewController? = self

        arkController = ARKController(type: .sceneKit, rootView: arkLayerView)

        arkController?.didUpdate = { c in
            guard let shouldSendNativeTime = blockSelf?.stateController?.shouldSendNativeTime() else { return }
            guard let shouldSendARKData = blockSelf?.stateController?.shouldSendARKData() else { return }
            guard let shouldSendCVData = blockSelf?.stateController?.shouldSendCVData() else { return }
            
            if shouldSendNativeTime {
                blockSelf?.sendNativeTime()
                var numberOfTimesSendNativeTimeWasCalled = blockSelf?.stateController?.state?.numberOfTimesSendNativeTimeWasCalled
                numberOfTimesSendNativeTimeWasCalled = (numberOfTimesSendNativeTimeWasCalled ?? 0) + 1
                blockSelf?.stateController?.state?.numberOfTimesSendNativeTimeWasCalled = numberOfTimesSendNativeTimeWasCalled ?? 1
            }

            if shouldSendARKData {
                blockSelf?.sendARKData()
            }

            if shouldSendCVData {
                if blockSelf?.sendComputerVisionData() ?? false {
                    blockSelf?.stateController?.state?.computerVisionFrameRequested = false
                    blockSelf?.arkController?.computerVisionFrameRequested = false
                }
            }
        }
        arkController?.didFailSession = { error in
            guard let error = error as NSError? else { return }
            blockSelf?.webController?.didReceiveError(error: error)

            if error.code == SENSOR_FAILED_ARKIT_ERROR_CODE {
                var currentARRequest = blockSelf?.stateController?.state?.aRRequest
                if currentARRequest?[WEB_AR_WORLD_ALIGNMENT] as? Bool ?? false {
                    // The session failed because the compass (heading) couldn't be initialized. Fallback the session to ARWorldAlignmentGravity
                    currentARRequest?[WEB_AR_WORLD_ALIGNMENT] = false
                    blockSelf?.stateController?.setARRequest(currentARRequest)
                    return
                }
            }

            var errorMessage = "ARKit Error"
            switch error.code {
                case Int(CAMERA_ACCESS_NOT_AUTHORIZED_ARKIT_ERROR_CODE):
                    // If there is a camera access error, do nothing
                    return
                case Int(UNSUPPORTED_CONFIGURATION_ARKIT_ERROR_CODE):
                    errorMessage = UNSUPPORTED_CONFIGURATION_ARKIT_ERROR_MESSAGE
                case Int(SENSOR_UNAVAILABLE_ARKIT_ERROR_CODE):
                    errorMessage = SENSOR_UNAVAILABLE_ARKIT_ERROR_MESSAGE
                case Int(SENSOR_FAILED_ARKIT_ERROR_CODE):
                    errorMessage = SENSOR_FAILED_ARKIT_ERROR_MESSAGE
                case Int(WORLD_TRACKING_FAILED_ARKIT_ERROR_CODE):
                    errorMessage = WORLD_TRACKING_FAILED_ARKIT_ERROR_MESSAGE
                default:
                    break
            }

            DispatchQueue.main.async(execute: {
                blockSelf?.messageController?.hideMessages()
                blockSelf?.messageController?.showMessageAboutFailSession(withMessage: errorMessage) {
                    DispatchQueue.main.async(execute: {
                        self.webController?.loadBlankHTMLString()
                    })
                }
            })
        }

        guard let hasPlanes = blockSelf?.arkController?.hasPlanes() else { return }

        arkController?.didUpdateWindowSize = {
            blockSelf?.webController?.updateWindowSize()
        }

        animator?.animate(arkLayerView, toFade: false)

        guard let state = stateController?.state else { return }
        arkController?.startSession(with: state)

        // Log event when we start an AR session
        AnalyticsManager.sharedInstance.sendEvent(category: .action, method: .webXR, object: .initialize)
    }

    func setupWebController() {
        CLEAN_VIEW(v: webLayerView)

        weak var blockSelf: ViewController? = self

        self.webController = WebController(rootView: webLayerView)
        if !ARKController.supportsARFaceTrackingConfiguration() {
            webController?.hideCameraFlipButton()
        }
        webController?.animator = animator
        webController?.onStartLoad = {
            if blockSelf?.arkController != nil {
                let lastURL = blockSelf?.webController?.lastURL
                let currentURL = blockSelf?.webController?.webView?.url?.absoluteString

                if (lastURL == currentURL) {
                    // Page reload
                    blockSelf?.arkController?.removeAllAnchorsExceptPlanes()
                }
            }
            blockSelf?.stateController?.setWebXR(false)
        }

        webController?.onFinishLoad = {
            //         [blockSelf hideSplashWithCompletion:^
            //          { }];
        }

        webController?.onInitAR = { uiOptionsDict in
            blockSelf?.stateController?.setShowOptions(showOptionsFormDict(uiOptionsDict))

            blockSelf?.stateController?.applyOnEnterForegroundAction()
            blockSelf?.stateController?.applyOnDidReceiveMemoryAction()
        }

        webController?.onError = { error in
            if let error = error {
                blockSelf?.showWebError(error as NSError)
            }
        }

        webController?.onWatchAR = { request in
            blockSelf?.handleOnWatchAR(withRequest: request)
        }

        webController?.onStopAR = {
            blockSelf?.stateController?.setWebXR(false)
            blockSelf?.stateController?.setShowMode(.nothing)
        }

        webController?.onJSUpdateData = {
            return blockSelf?.commonData() ?? [:]
        }

        webController?.loadURL = { url in
            blockSelf?.webController?.loadURL(url)
        }

        webController?.onSetUI = { uiOptionsDict in
            blockSelf?.stateController?.setShowOptions(showOptionsFormDict(uiOptionsDict))
        }

        webController?.onHitTest = { mask, x, y, result in
            let array = blockSelf?.arkController?.hitTestNormPoint(CGPoint(x: x, y: y), types: UInt(mask))
            result(array)
        }

        webController?.onAddAnchor = { name, transformArray, result in
            if blockSelf?.arkController?.addAnchor(name, transform: transformArray) != nil {
                if let anArray = transformArray {
                    result([WEB_AR_UUID_OPTION: name ?? 0, WEB_AR_TRANSFORM_OPTION: anArray])
                }
            } else {
                result([:])
            }
        }

        webController?.onRemoveObjects = { objects in
            blockSelf?.arkController?.removeAnchors(objects)
        }

        webController?.onDebugButtonToggled = { selected in
            blockSelf?.stateController?.setShowMode(selected ? ShowMode.multiDebug : ShowMode.multi)
        }
        
        webController?.onSettingsButtonTapped = {
            // Before showing the settings popup, we hide the bar and the debug buttons so they are not in the way
            // After dismissing the popup, we show them again.
            let settingsViewController = SettingsViewController()
            let navigationController = UINavigationController(rootViewController: settingsViewController)
            weak var weakSettingsViewController = settingsViewController
            settingsViewController.onDoneButtonTapped = {
                weakSettingsViewController?.dismiss(animated: true)
                blockSelf?.webController?.showBar(true)
                blockSelf?.stateController?.setShowMode(.multi)
            }

            blockSelf?.webController?.showBar(false)
            blockSelf?.webController?.hideKeyboard()
            blockSelf?.stateController?.setShowMode(.nothing)
            blockSelf?.present(navigationController, animated: true)
        }

        webController?.onComputerVisionDataRequested = {
            blockSelf?.stateController?.state?.computerVisionFrameRequested = true
            blockSelf?.arkController?.computerVisionFrameRequested = true
        }

        webController?.onResetTrackingButtonTapped = {

            blockSelf?.messageController?.showMessageAboutResetTracking({ option in
                guard let state = blockSelf?.stateController?.state else { return }
                switch option {
                    case .ResetTracking:
                        blockSelf?.arkController?.runSessionResettingTrackingAndRemovingAnchors(with: state)
                    case .RemoveExistingAnchors:
                        blockSelf?.arkController?.runSessionRemovingAnchors(with: state)
                    case .SaveWorldMap:
                        blockSelf?.arkController?.saveWorldMap()
                    case .LoadSavedWorldMap:
                        blockSelf?.arkController?.loadSavedMap()
                    default:
                        break
                }
            })
        }

        webController?.onStartSendingComputerVisionData = {
            blockSelf?.stateController?.state?.sendComputerVisionData = true
        }

        webController?.onStopSendingComputerVisionData = {
            blockSelf?.stateController?.state?.sendComputerVisionData = false
        }

        webController?.onActivateDetectionImage = { imageName, completion in
            blockSelf?.arkController?.activateDetectionImage(imageName, completion: completion)
        }

        webController?.onGetWorldMap = { completion in
//            let completion = completion as? GetWorldMapCompletionBlock
            blockSelf?.arkController?.getWorldMap(completion)
        }

        webController?.onSetWorldMap = { dictionary, completion in
            blockSelf?.arkController?.setWorldMap(dictionary, completion: completion)
        }

        webController?.onDeactivateDetectionImage = { imageName, completion in
            blockSelf?.arkController?.deactivateDetectionImage(imageName, completion: completion)
        }

        webController?.onDestroyDetectionImage = { imageName, completion in
            blockSelf?.arkController?.destroyDetectionImage(imageName, completion: completion)
        }

        webController?.onCreateDetectionImage = { dictionary, completion in
            blockSelf?.arkController?.createDetectionImage(dictionary, completion: completion)
        }

        webController?.onSwitchCameraButtonTapped = {
            blockSelf?.arkController?.switchCameraButtonTapped()
        }

        guard let wasMemoryWarning = stateController?.wasMemoryWarning() else { return }
        if wasMemoryWarning {
            stateController?.applyOnDidReceiveMemoryAction()
        } else {
            let requestedURL = UserDefaults.standard.string(forKey: REQUESTED_URL_KEY)
            if requestedURL != nil && !(requestedURL == "") {
                UserDefaults.standard.set(nil, forKey: REQUESTED_URL_KEY)
                webController?.loadURL(requestedURL)
            } else {
                let lastURL = UserDefaults.standard.string(forKey: LAST_URL_KEY)
                if lastURL != nil {
                    webController?.loadURL(lastURL)
                } else {
                    let homeURL = UserDefaults.standard.string(forKey: Constant.homeURLKey())
                    if homeURL != nil && !(homeURL == "") {
                        webController?.loadURL(homeURL)
                    } else {
                        webController?.loadURL(WEB_URL)
                    }
                }
            }
        }
    }

    func setupOverlayController() {
        CLEAN_VIEW(v: hotLayerView)

        weak var blockSelf: ViewController? = self

        let showAction: HotAction = { any in
            blockSelf?.stateController?.invertShowMode()
        }

        let debugAction: HotAction = { any in
            blockSelf?.stateController?.invertDebugMode()
        }

        hotLayerView.processTouchInSubview = true

        self.overlayController = UIOverlayController(rootView: hotLayerView, showAction: showAction, debugAction: debugAction)

        overlayController?.animator = animator
        
        guard let showMode = stateController?.state?.showMode else { return }
        guard let showOptions = stateController?.state?.showOptions else { return }
        overlayController?.setMode(showMode)
        overlayController?.setOptions(showOptions)
    }

// MARK: Cleanups
    func cleanupCommonControllers() {
        animator?.clean()
        stateController?.state = AppState.defaultState()
        messageController?.clean()
    }

    func cleanupTargetControllers() {
        self.locationManager = nil

        cleanWebController()
        cleanARKController()
        cleanOverlay()
    }

    func cleanARKController() {
        CLEAN_VIEW(v: arkLayerView)
        self.arkController = nil
    }

    func cleanWebController() {
        webController?.clean()
        CLEAN_VIEW(v: webLayerView)
        self.webController = nil
    }

    func cleanOverlay() {
        overlayController?.clean()
        CLEAN_VIEW(v: hotLayerView)
        self.overlayController = nil
    }

// MARK: Splash
    func showSplash(with completion: @escaping UICompletion) {
        splashLayerView.alpha = 1
        RUN_UI_COMPLETION_ASYNC_MAIN(c: completion)
    }

    func hideSplash(with completion: @escaping UICompletion) {
        splashLayerView.alpha = 0
        RUN_UI_COMPLETION_ASYNC_MAIN(c: completion)
    }

// MARK: MemoryWarning
    func processMemoryWarning() {
        stateController?.saveDidReceiveMemoryWarning(onURL: webController?.lastURL)
        cleanupCommonControllers()
        //    [self showSplashWithCompletion:^
        //     {
        cleanupTargetControllers()
        //     }];

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(WAITING_TIME_ON_MEMORY_WARNING * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
            self.setupTargetControllers()

            //                       [self hideSplashWithCompletion:^
            //                        {}];
        })
    }

// MARK: Data
    func commonData() -> [AnyHashable : Any]? {
        var dictionary = [AnyHashable : Any]()

        if let aData = arkController?.arkData() {
            dictionary = aData
        }

        return dictionary
    }

    func sendARKData() {
        // BLAIR:  Why are we doing this copy above?  Seems like
        //    [[self webController] sendARData:[self commonData]];
        webController?.sendARData(arkController?.arkData())
    }

    func sendComputerVisionData() -> Bool {
        let data = arkController?.computerVisionData()
        if data != nil {
            webController?.sendComputerVisionData(data)
            return true
        }
        return false
    }

    func sendNativeTime() {
        guard let currentFrame = arkController?.currentFrameTimeInMilliseconds() else { return }
        webController?.sendNativeTime(currentFrame)
    }

    // MARK: Web
    
    func showWebError(_ error: NSError?) {
        guard let error = error else { return }
        if error.code == INTERNET_OFFLINE_CODE {
            stateController?.setShowMode(.nothing)
            stateController?.saveNotReachable(onURL: webController?.lastURL)
            messageController?.showMessageAboutConnectionRequired()
        } else if error.code == USER_CANCELLED_LOADING_CODE {
            // Desired behavior is similar to Safari, i.e. no alerts or messages presented upon user-initiated cancel
        } else {
            messageController?.showMessageAboutWebError(error, withCompletion: { reload in
                
                if reload {
                    self.loadURL(nil)
                } else {
                    self.stateController?.applyOnMessageShowMode()
                }
            })
        }
    }

    func loadURL(_ url: String?) {
        if url == nil {
            webController?.reload()
        } else {
            webController?.loadURL(url)
        }

        stateController?.setWebXR(false)
    }

    func handleOnWatchAR(withRequest request: [AnyHashable : Any]?) {
        weak var blockSelf: ViewController? = self

        arkController?.computerVisionDataEnabled = false
        stateController?.state?.userGrantedSendingComputerVisionData = false
        stateController?.state?.userGrantedSendingWorldStateData = .denied
        stateController?.state?.sendComputerVisionData = true
        stateController?.state?.askedComputerVisionData = false
        stateController?.state?.askedWorldStateData = false
        arkController?.sendingWorldSensingDataAuthorizationStatus = .notDetermined

        if (request?[WEB_AR_CV_INFORMATION_OPTION] as? Bool ?? false) {
            messageController?.showMessageAboutAccessingTheCapturedImage({ granted in
                blockSelf?.webController?.userGrantedComputerVisionData(granted)
                if blockSelf?.arkController != nil {
                    blockSelf?.arkController?.computerVisionDataEnabled = granted

                    // Approving computer vision data implicitly approves the world sensing data
                    blockSelf?.arkController?.sendingWorldSensingDataAuthorizationStatus = granted ? .authorized : .denied
                }
                blockSelf?.stateController?.state?.askedComputerVisionData = true
                blockSelf?.stateController?.state?.userGrantedSendingComputerVisionData = granted

                blockSelf?.stateController?.state?.askedWorldStateData = true
                blockSelf?.stateController?.state?.userGrantedSendingWorldStateData = granted ? .authorized : .denied
            })
        } else if (request?[WEB_AR_WORLD_SENSING_DATA_OPTION] as? Bool ?? false) {
            messageController?.showMessageAboutAccessingWorldSensingData({ access in
                
                blockSelf?.stateController?.state?.askedWorldStateData = true
                
                switch access {
                case SendWorldSensingDataAuthorizationState.authorized,
                     SendWorldSensingDataAuthorizationState.singlePlane:
                    blockSelf?.webController?.userGrantedSendingWorldSensingData(true)
                    blockSelf?.arkController?.sendingWorldSensingDataAuthorizationStatus = access
                    blockSelf?.stateController?.state?.userGrantedSendingWorldStateData = access
                default:
                    blockSelf?.webController?.userGrantedSendingWorldSensingData(false)
                    blockSelf?.arkController?.sendingWorldSensingDataAuthorizationStatus = .denied
                    blockSelf?.stateController?.state?.userGrantedSendingWorldStateData = .denied
                }
                
                if access == SendWorldSensingDataAuthorizationState.singlePlane && blockSelf?.stateController?.state?.shouldShowLiteModePopup ?? false {
                    blockSelf?.stateController?.state?.shouldShowLiteModePopup = false
                    blockSelf?.messageController?.showMessage(withTitle: "Lite Mode Started", message: "Only the first plane scanned will be shared with this website. No facial recognition nor image recognition will be shared.", hideAfter: 6)
                }
            }, url: webController?.webView?.url)
        } else {
            // if neither is requested, we'll actually set it to denied!
            blockSelf?.arkController?.sendingWorldSensingDataAuthorizationStatus = .denied
        }

        stateController?.setARRequest(request)
        stateController?.setWebXR(true)
        stateController?.state?.numberOfTimesSendNativeTimeWasCalled = 0
    }
    
    func CLEAN_VIEW(v: LayerView) {
        for view in v.subviews {
            view.removeFromSuperview()
        }
    }
}

func RUN_UI_COMPLETION_ASYNC_MAIN(c: @escaping UICompletion) {
    DispatchQueue.main.async(execute: {
        c()
    })
}
