import Foundation
import WebKit

typealias OnLoad = () -> Void
typealias OnInit = ([AnyHashable : Any]?) -> Void
typealias OnWebError = (Error?) -> Void
typealias OnUpdateTransfer = ([AnyHashable : Any]?) -> Void
typealias ResultBlock = ([AnyHashable : Any]?) -> Void
typealias ResultArrayBlock = ([Any]?) -> Void
typealias ImageDetectedBlock = ([AnyHashable : Any]?) -> Void
typealias ActivateDetectionImageCompletionBlock = (Bool, String?, [AnyHashable : Any]?) -> Void
typealias CreateDetectionImageCompletionBlock = (Bool, String?) -> Void
typealias GetWorldMapCompletionBlock = (Bool, String?, [AnyHashable : Any]?) -> Void
typealias SetWorldMapCompletionBlock = (Bool, String?) -> Void
typealias OnRemoveObjects = ([Any]?) -> Void
typealias OnJSUpdateData = () -> [AnyHashable : Any]
typealias OnLoadURL = (String?) -> Void
typealias OnSetUI = ([AnyHashable : Any]?) -> Void
typealias OnHitTest = (Int, CGFloat, CGFloat, @escaping ResultArrayBlock) -> Void
typealias OnAddAnchor = (String?, [Any]?, @escaping ResultBlock) -> Void
typealias OnDebugButtonToggled = (Bool) -> Void
typealias OnSettingsButtonTapped = () -> Void
typealias OnWatchAR = ([AnyHashable : Any]?) -> Void
typealias OnComputerVisionDataRequested = () -> Void
typealias OnStopAR = () -> Void
typealias OnResetTrackingButtonTapped = () -> Void
typealias OnSwitchCameraButtonTapped = () -> Void
typealias OnStartSendingComputerVisionData = () -> Void
typealias OnStopSendingComputerVisionData = () -> Void
typealias OnAddImageAnchor = ([AnyHashable : Any]?, @escaping ImageDetectedBlock) -> Void
typealias OnActivateDetectionImage = (String?, @escaping ActivateDetectionImageCompletionBlock) -> Void
typealias OnDeactivateDetectionImage = (String?, @escaping CreateDetectionImageCompletionBlock) -> Void
typealias OnDestroyDetectionImage = (String?, @escaping CreateDetectionImageCompletionBlock) -> Void
typealias OnCreateDetectionImage = ([AnyHashable : Any]?, @escaping CreateDetectionImageCompletionBlock) -> Void
typealias OnGetWorldMap = (@escaping GetWorldMapCompletionBlock) -> Void
typealias OnSetWorldMap = ([AnyHashable : Any]?, @escaping SetWorldMapCompletionBlock) -> Void
typealias WebCompletion = (Any?, Error?) -> Void

class WebController: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    @objc var onInitAR: OnInit?
    @objc var onError: OnWebError?
    @objc var onIOSUpdate: OnUpdateTransfer?
    @objc var loadURL: OnLoadURL?
    @objc var onJSUpdate: OnUpdateTransfer?
    @objc var onJSUpdateData: OnJSUpdateData?
    @objc var onRemoveObjects: OnRemoveObjects?
    @objc var onSetUI: OnSetUI?
    @objc var onHitTest: OnHitTest?
    @objc var onAddAnchor: OnAddAnchor?
    @objc var onStartLoad: OnLoad?
    @objc var onFinishLoad: OnLoad?
    @objc var onDebugButtonToggled: OnDebugButtonToggled?
    @objc var onSettingsButtonTapped: OnSettingsButtonTapped?
    @objc var onWatchAR: OnWatchAR?
    @objc var onComputerVisionDataRequested: OnComputerVisionDataRequested?
    @objc var onStopAR: OnStopAR?
    @objc var onResetTrackingButtonTapped: OnResetTrackingButtonTapped?
    @objc var onSwitchCameraButtonTapped: OnSwitchCameraButtonTapped?
    @objc var onStartSendingComputerVisionData: OnStartSendingComputerVisionData?
    @objc var onStopSendingComputerVisionData: OnStopSendingComputerVisionData?
    @objc var onAddImageAnchor: OnAddImageAnchor?
    @objc var onActivateDetectionImage: OnActivateDetectionImage?
    @objc var onDeactivateDetectionImage: OnDeactivateDetectionImage?
    @objc var onDestroyDetectionImage: OnDestroyDetectionImage?
    @objc var onCreateDetectionImage: OnCreateDetectionImage?
    @objc var onGetWorldMap: OnGetWorldMap?
    @objc var onSetWorldMap: OnSetWorldMap?
    @objc var animator: Animator?
    @objc weak var barViewHeightAnchorConstraint: NSLayoutConstraint?
    @objc weak var webViewTopAnchorConstraint: NSLayoutConstraint?
    @objc var webViewLeftAnchorConstraint: NSLayoutConstraint?
    @objc var webViewRightAnchorConstraint: NSLayoutConstraint?
    @objc var lastXRVisitedURL = ""

    @objc init(rootView: UIView?) {
        super.init()
        
        setupWebView(withRootView: rootView)
        setupWebContent()
        setupWebUI()
        setupBarView()
    }

    @objc func viewWillTransition(to size: CGSize) {
        layout()

        // This message is not being used by the polyfyill
        // [self callWebMethod:WEB_AR_IOS_VIEW_WILL_TRANSITION_TO_SIZE_MESSAGE param:NSStringFromCGSize(size) webCompletion:debugCompletion(@"viewWillTransitionToSize")];
    }

    @objc func loadURL(_ theUrl: String?) {
        goFullScreen()

        var url: URL?
        if theUrl?.hasPrefix("http://") ?? false || theUrl?.hasPrefix("https://") ?? false {
            url = URL(string: theUrl ?? "")
        } else {
            url = URL(string: "https://\(theUrl ?? "")")
        }

        if url != nil {
            let scheme = url?.scheme

            if scheme != nil && WKWebView.handlesURLScheme(scheme ?? "") {
                var r: URLRequest? = nil
                if let anUrl = url {
                    r = URLRequest(url: anUrl, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 60)
                }

                URLCache.shared.removeAllCachedResponses()

                if let aR = r {
                    webView?.load(aR)
                }

                self.lastURL = url?.absoluteString ?? ""
                return
            }
        }
        //if onError
        onError?(nil)
    }

    @objc func loadBlankHTMLString() {
        webView?.loadHTMLString("<html></html>", baseURL: webView?.url)
    }

    @objc func reload() {
        let url = (barView?.urlFieldText()?.count ?? 0) > 0 ? barView?.urlFieldText() : lastURL
        loadURL(url)
    }

    @objc func clean() {
        cleanWebContent()

        webView?.stopLoading()

        webView?.configuration.processPool = WKProcessPool()
        URLCache.shared.removeAllCachedResponses()
    }

    @objc func setup(forWebXR webXR: Bool) {
        DispatchQueue.main.async(execute: {
            self.barView?.hideKeyboard()
            self.barView?.setDebugVisible(webXR)
            self.barView?.setRestartTrackingVisible(webXR)
            let webViewTopAnchorConstraintConstant: Float = webXR ? 0.0 : Float(Constant.urlBarHeight())
            self.webViewTopAnchorConstraint?.constant = CGFloat(webViewTopAnchorConstraintConstant)
            self.webView?.superview?.setNeedsLayout()
            self.webView?.superview?.layoutIfNeeded()

            let backColor = webXR ? UIColor.clear : UIColor.white
            self.webView?.superview?.backgroundColor = backColor

            self.animator?.animate(self.webView?.superview, to: backColor)
        })
    }

    @objc func showBar(_ showBar: Bool) {
        print("Show bar: \(showBar ? "Yes" : "No")")
        barView?.superview?.layoutIfNeeded()

        let topAnchorConstant: Float = showBar ? 0.0 : Float(0.0 - Constant.urlBarHeight() * 2)
        barViewTopAnchorConstraint?.constant = CGFloat(topAnchorConstant)

        UIView.animate(withDuration: Constant.urlBarAnimationTimeInSeconds(), animations: {
            self.barView?.superview?.layoutIfNeeded()
        })
    }

    @objc func showDebug(_ showDebug: Bool) {
        callWebMethod(WEB_AR_IOS_SHOW_DEBUG, paramJSON: [WEB_AR_UI_DEBUG_OPTION: showDebug ? true : false], webCompletion: debugCompletion(name: "showDebug"))
    }

    @objc func wasARInterruption(_ interruption: Bool) {
        let message = interruption ? WEB_AR_IOS_START_RECORDING_MESSAGE : WEB_AR_IOS_INTERRUPTION_ENDED_MESSAGE

        callWebMethod(message, param: "", webCompletion: debugCompletion(name: "ARinterruption"))
    }

    @objc func didBackgroundAction(_ background: Bool) {
        let message = background ? WEB_AR_IOS_DID_MOVE_BACK_MESSAGE : WEB_AR_IOS_WILL_ENTER_FOR_MESSAGE

        callWebMethod(message, param: "", webCompletion: debugCompletion(name: "backgroundAction"))
    }

    @objc func didChangeARTrackingState(_ state: String?) {
        callWebMethod(WEB_AR_IOS_TRACKING_STATE_MESSAGE, param: state, webCompletion: debugCompletion(name: "arkitDidChangeTrackingState"))
    }

    @objc func updateWindowSize() {
        let size: CGSize? = webView?.frame.size
        let sizeDictionary = [WEB_AR_IOS_SIZE_WIDTH_PARAMETER: size?.width ?? 0, WEB_AR_IOS_SIZE_HEIGHT_PARAMETER: size?.height ?? 0]
        callWebMethod(WEB_AR_IOS_WINDOW_RESIZE_MESSAGE, paramJSON: sizeDictionary, webCompletion: debugCompletion(name: WEB_AR_IOS_WINDOW_RESIZE_MESSAGE))
    }

    func didReceiveMemoryWarning() {
        callWebMethod(WEB_AR_IOS_DID_RECEIVE_MEMORY_WARNING_MESSAGE, param: "", webCompletion: debugCompletion(name: "iosDidReceiveMemoryWarning"))
    }

    // Tony: Doesn't appear a Bool previously returned by sendARData was used anywhere, I removed the return during conversion to Swift
    @objc func sendARData(_ data: [AnyHashable : Any]?) {
        // Tony: Unclear what this bool was used for in Objective-C
//        let CHECK_UPDATE_CALL = false
        if transferCallback != "" && data != nil {
            callWebMethod(transferCallback, paramJSON: data, webCompletion: nil)
//            print("sendARData success")
        }
//        print("sendARData did not send data")
    }

    @objc func hideKeyboard() {
        barView?.hideKeyboard()
    }

    @objc func didReceiveError(error: NSError) {
        let errorDictionary = [WEB_AR_IOS_ERROR_DOMAIN_PARAMETER: error.domain, WEB_AR_IOS_ERROR_CODE_PARAMETER: error.code, WEB_AR_IOS_ERROR_MESSAGE_PARAMETER: error.localizedDescription] as [String : Any]
        callWebMethod(WEB_AR_IOS_ERROR_MESSAGE, paramJSON: errorDictionary, webCompletion: debugCompletion(name: WEB_AR_IOS_ERROR_MESSAGE))
    }

    @objc func sendComputerVisionData(_ computerVisionData: [AnyHashable : Any]?) {
        callWebMethod("onComputerVisionData", paramJSON: computerVisionData, webCompletion: { param, error in
            if error != nil {
                print("Error onComputerVisionData: \(error?.localizedDescription ?? "")")
            }
        })
    }

    @objc func userGrantedComputerVisionData(_ granted: Bool) {
        callWebMethod(WEB_AR_IOS_USER_GRANTED_CV_DATA, paramJSON: ["granted": granted], webCompletion: debugCompletion(name: WEB_AR_IOS_USER_GRANTED_CV_DATA))
    }

    @objc func isDebugButtonSelected() -> Bool {
        return barView?.isDebugButtonSelected() ?? false
    }

    @objc func sendNativeTime(_ nativeTime: TimeInterval) {
        print("Sending native time: \(nativeTime)")
        let jsonData = ["nativeTime": nativeTime]
        callWebMethod("setNativeTime", paramJSON: jsonData, webCompletion: { param, error in
            if error != nil {
                print("Error setNativeTime: \(error?.localizedDescription ?? "")")
            }
        })
    }

    @objc func userGrantedSendingWorldSensingData(_ granted: Bool) {
        callWebMethod(WEB_AR_IOS_USER_GRANTED_WORLD_SENSING_DATA, paramJSON: ["granted": granted], webCompletion: debugCompletion(name: WEB_AR_IOS_USER_GRANTED_CV_DATA))
    }

    @objc func hideCameraFlipButton() {
        barView?.hideCameraFlipButton()
    }
    private weak var rootView: UIView?
    @objc weak var webView: WKWebView?
    private weak var contentController: WKUserContentController?
    private var transferCallback = ""
    @objc var lastURL = ""
    private weak var barView: BarView?
    private weak var barViewTopAnchorConstraint: NSLayoutConstraint?
    private var documentReadyState = ""

// MARK: Interface

    deinit {
        DDLogDebug("WebController dealloc")
    }

    func goHome() {
        print("going home")
        let homeURL = UserDefaults.standard.string(forKey: Constant.homeURLKey())
        if homeURL != nil && !(homeURL == "") {
            loadURL(homeURL)
        } else {
            loadURL(WEB_URL)
        }
    }

// MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        //DDLogDebug(@"Received message: %@ , body: %@", [message name], [message body]);

        weak var blockSelf: WebController? = self
        guard let messageBody = message.body as? [String: Any] else { return }
        if (message.name == WEB_AR_INIT_MESSAGE) {
            let params = [WEB_IOS_DEVICE_UUID_OPTION: UIDevice.current.identifierForVendor?.uuidString ?? 0, WEB_IOS_IS_IPAD_OPTION: UIDevice.current.userInterfaceIdiom == .pad, WEB_IOS_SYSTEM_VERSION_OPTION: UIDevice.current.systemVersion, WEB_IOS_SCREEN_SCALE_OPTION: UIScreen.main.nativeScale, WEB_IOS_SCREEN_SIZE_OPTION: NSCoder.string(for: UIScreen.main.nativeBounds.size)] as [String : Any]

            DDLogDebug("Init AR send - \(params.debugDescription)")

            callWebMethod((message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String, paramJSON: params, webCompletion: { param, error in

                if error == nil {
                    DDLogDebug("Init AR Success")
                    guard let arRequestOption = messageBody[WEB_AR_REQUEST_OPTION] as? [String: Any] else { return }
                    guard let arUIOption = arRequestOption[WEB_AR_UI_OPTION] as? [String: Any] else { return }
                    blockSelf?.onInitAR?(arUIOption)
                } else {
                    DDLogDebug("Init AR Error")
                    blockSelf?.onError?(error)
                }
            })
        } else if (message.name == WEB_AR_LOAD_URL_MESSAGE) {
            loadURL?(messageBody[WEB_AR_URL_OPTION] as? String)
        } else if (message.name == WEB_AR_START_WATCH_MESSAGE) {
            self.transferCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String ?? ""

            onWatchAR?(messageBody[WEB_AR_REQUEST_OPTION] as? [AnyHashable: Any])
        } else if (message.name == WEB_AR_ON_JS_UPDATE_MESSAGE) {
            sendARData(blockSelf?.onJSUpdateData?())
        } else if (message.name == WEB_AR_STOP_WATCH_MESSAGE) {
            self.transferCallback = ""

            onStopAR?()

            callWebMethod((message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String, param: "", webCompletion: nil)
        } else if (message.name == WEB_AR_SET_UI_MESSAGE) {
            onSetUI?(messageBody)
        } else if (message.name == WEB_AR_HIT_TEST_MESSAGE) {
            let hitCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String
            let type = Int(messageBody[WEB_AR_TYPE_OPTION] as? Int ?? 0)
            let x = CGFloat(messageBody[WEB_AR_X_POSITION_OPTION] as? CGFloat ?? 0.0)
            let y = CGFloat(messageBody[WEB_AR_Y_POSITION_OPTION] as? CGFloat ?? 0.0)

            onHitTest?(type, x, y, { results in
                //DDLogDebug(@"Hit test - %@", [results debugDescription]);
                blockSelf?.callWebMethod(hitCallback, paramJSON: results, webCompletion: debugCompletion(name: "onHitTest"))
            })
        } else if (message.name == WEB_AR_ADD_ANCHOR_MESSAGE) {
            let hitCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String
            let name = (message.body as? [AnyHashable : Any])?[WEB_AR_UUID_OPTION] as? String
            guard let transform = (message.body as? [AnyHashable : Any])?[WEB_AR_TRANSFORM_OPTION] as? [Any] else { return }

            onAddAnchor?(name, transform, { results in
                blockSelf?.callWebMethod(hitCallback, paramJSON: results, webCompletion: debugCompletion(name: "onAddAnchor"))
            })
        } else if (message.name == WEB_AR_REQUEST_CV_DATA_MESSAGE) {
            if onComputerVisionDataRequested != nil {
                onComputerVisionDataRequested?()
            }
        } else if (message.name == WEB_AR_START_SENDING_CV_DATA_MESSAGE) {
            if onStartSendingComputerVisionData != nil {
                onStartSendingComputerVisionData?()
            }
        } else if (message.name == WEB_AR_STOP_SENDING_CV_DATA_MESSAGE) {
            if onStopSendingComputerVisionData != nil {
                onStopSendingComputerVisionData?()
            }
        } else if (message.name == WEB_AR_REMOVE_ANCHORS_MESSAGE) {
            let anchorIDs = message.body as? [Any]
            if onRemoveObjects != nil {
                onRemoveObjects?(anchorIDs)
            }
        } else if (message.name == WEB_AR_ADD_IMAGE_ANCHOR) {
            let imageAnchorInfoDictionary = messageBody
            let createImageAnchorCallback = messageBody[WEB_AR_CALLBACK_OPTION] as? String
            if onAddImageAnchor != nil {
                onAddImageAnchor?(imageAnchorInfoDictionary, { imageAnchor in
                    blockSelf?.callWebMethod(createImageAnchorCallback, paramJSON: imageAnchor, webCompletion: nil)
                })
            }
        } else if (message.name == WEB_AR_CREATE_IMAGE_ANCHOR_MESSAGE) {
            let imageAnchorInfoDictionary = messageBody
            let createDetectionImageCallback = messageBody[WEB_AR_CALLBACK_OPTION] as? String
            if onCreateDetectionImage != nil {
                onCreateDetectionImage?(imageAnchorInfoDictionary, { success, errorString in
                    var responseDictionary = [String : Any]()
                    responseDictionary["created"] = success
                    if errorString != nil {
                        responseDictionary["error"] = errorString
                    }
                    blockSelf?.callWebMethod(createDetectionImageCallback, paramJSON: responseDictionary, webCompletion: nil)
                })
            }
        } else if (message.name == WEB_AR_ACTIVATE_DETECTION_IMAGE_MESSAGE) {
            let imageAnchorInfoDictionary = messageBody
            let imageName = imageAnchorInfoDictionary[WEB_AR_DETECTION_IMAGE_NAME_OPTION] as? String
            let activateDetectionImageCallback = messageBody[WEB_AR_CALLBACK_OPTION] as? String
            if onActivateDetectionImage != nil {
                onActivateDetectionImage?(imageName, { success, errorString, imageAnchor in
                    var responseDictionary = [AnyHashable : Any]()
                    responseDictionary["activated"] = success
                    if errorString != nil {
                        responseDictionary["error"] = errorString ?? ""
                    } else {
                        if let anAnchor = imageAnchor {
                            responseDictionary["imageAnchor"] = anAnchor
                        }
                    }
                    blockSelf?.callWebMethod(activateDetectionImageCallback, paramJSON: responseDictionary, webCompletion: nil)
                })
            }
        } else if (message.name == WEB_AR_DEACTIVATE_DETECTION_IMAGE_MESSAGE) {
            let imageAnchorInfoDictionary = message.body as? [AnyHashable : Any]
            let imageName = imageAnchorInfoDictionary?[WEB_AR_DETECTION_IMAGE_NAME_OPTION] as? String
            let deactivateDetectionImageCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String
            if onDeactivateDetectionImage != nil {
                onDeactivateDetectionImage?(imageName, { success, errorString in
                    var responseDictionary = [AnyHashable : Any]()
                    responseDictionary["deactivated"] = success
                    if errorString != nil {
                        responseDictionary["error"] = errorString ?? ""
                    }
                    blockSelf?.callWebMethod(deactivateDetectionImageCallback, paramJSON: responseDictionary, webCompletion: nil)
                })
            }
        } else if (message.name == WEB_AR_DESTROY_DETECTION_IMAGE_MESSAGE) {
            let imageAnchorInfoDictionary = message.body as? [AnyHashable : Any]
            let imageName = imageAnchorInfoDictionary?[WEB_AR_DETECTION_IMAGE_NAME_OPTION] as? String
            let destroyDetectionImageCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String
            if onDestroyDetectionImage != nil {
                onDestroyDetectionImage?(imageName, { success, errorString in
                    var responseDictionary = [AnyHashable : Any]()
                    responseDictionary["destroyed"] = success
                    if errorString != nil {
                        responseDictionary["error"] = errorString ?? ""
                    }
                    blockSelf?.callWebMethod(destroyDetectionImageCallback, paramJSON: responseDictionary, webCompletion: nil)
                })
            }
        } else if (message.name == WEB_AR_GET_WORLD_MAP_MESSAGE) {
            let getWorldMapCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String
            if onGetWorldMap != nil {
                onGetWorldMap?({ success, errorString, worldMap in
                    var responseDictionary = [AnyHashable : Any]()
                    responseDictionary["saved"] = success
                    if errorString != nil {
                        responseDictionary["error"] = errorString ?? ""
                    }
                    if worldMap != nil {
                        if let aMap = worldMap {
                            responseDictionary["worldMap"] = aMap
                        }
                    }
                    blockSelf?.callWebMethod(getWorldMapCallback, paramJSON: responseDictionary, webCompletion: nil)
                })
            }
        } else if (message.name == WEB_AR_SET_WORLD_MAP_MESSAGE) {
            let worldMapInfoDictionary = message.body as? [AnyHashable : Any]
            let setWorldMapCallback = (message.body as? [AnyHashable : Any])?[WEB_AR_CALLBACK_OPTION] as? String
            if onSetWorldMap != nil {
                onSetWorldMap?(worldMapInfoDictionary, { success, errorString in
                    var responseDictionary = [AnyHashable : Any]()
                    responseDictionary["loaded"] = success
                    if errorString != nil {
                        responseDictionary["error"] = errorString ?? ""
                    }
                    blockSelf?.callWebMethod(setWorldMapCallback, paramJSON: responseDictionary, webCompletion: nil)
                })
            }
        } else {
            DDLogError("Unknown message: \(message.body) ,for name: \(message.name)")
        }

    }

    func callWebMethod(_ name: String?, param: String?, webCompletion completion: WebCompletion?) {
        let jsonData = param != nil ? try? JSONSerialization.data(withJSONObject: [param], options: []) : Data()
        callWebMethod(name, jsonData: jsonData, webCompletion: completion)
    }

    func callWebMethod(_ name: String?, paramJSON: Any?, webCompletion completion: WebCompletion?) {
        var jsonData: Data? = nil
        if let aJSON = paramJSON {
            jsonData = paramJSON != nil ? try? JSONSerialization.data(withJSONObject: aJSON, options: []) : Data()
        }
        callWebMethod(name, jsonData: jsonData, webCompletion: completion)
    }

    func callWebMethod(_ name: String?, jsonData: Data?, webCompletion completion: WebCompletion?) {
        assert(name != nil, " Web Massage name is nil !")

        var jsString: String? = nil
        if let aData = jsonData {
            jsString = String(data: aData, encoding: .utf8)
        }
        let jsScript = "\(name ?? "")(\(jsString ?? ""))"

        webView?.evaluateJavaScript(jsScript, completionHandler: completion)
    }

// MARK: WKUIDelegate, WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DDLogDebug("didStartProvisionalNavigation - \(String(describing: navigation))\n on thread \(Thread.current.description)")

        self.webView?.addObserver(self as NSObject, forKeyPath: "estimatedProgress", options: .new, context: nil)
        documentReadyState = ""

        onStartLoad?()

        barView?.startLoading(self.webView?.url?.absoluteString)
        barView?.setBackEnabled(self.webView?.canGoBack ?? false)
        barView?.setForwardEnabled(self.webView?.canGoForward ?? false)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DDLogDebug("didFinishNavigation - \(String(describing: navigation))")
        //    NSString* loadedURL = [[[self webView] URL] absoluteString];
        //    [self setLastURL:loadedURL];
        //
        //    [[NSUserDefaults standardUserDefaults] setObject:loadedURL forKey:LAST_URL_KEY];
        //
        //    [self onFinishLoad]();
        //
        //    [[self barView] finishLoading:[[[self webView] URL] absoluteString]];
        //    [[self barView] setBackEnabled:[[self webView] canGoBack]];
        //    [[self barView] setForwardEnabled:[[self webView] canGoForward]];
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DDLogError("Web Error - \(error)")

        if self.webView?.observationInfo != nil {
            self.webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        } else {
            print("No Observers Found on WebView in WebController didFailProvisionalNavigation Check")
        }

        if shouldShowError(error: error as NSError) {
            onError?(error)
        }

        barView?.finishLoading(self.webView?.url?.absoluteString)
        barView?.setBackEnabled(self.webView?.canGoBack ?? false)
        barView?.setForwardEnabled(self.webView?.canGoForward ?? false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DDLogError("Web Error - \(error)")

        if self.webView?.observationInfo != nil {
            self.webView?.removeObserver(self as NSObject, forKeyPath: "estimatedProgress")
        } else {
            print("No Observers Found on WebView in WebController didFail Check")
        } 

        if shouldShowError(error: error as NSError) {
            onError?(error)
        }

        barView?.finishLoading(self.webView?.url?.absoluteString)
        barView?.setBackEnabled(self.webView?.canGoBack ?? false)
        barView?.setForwardEnabled(self.webView?.canGoForward ?? false)
    }

    func webView(_ webView: WKWebView, shouldPreviewElement elementInfo: WKPreviewElementInfo) -> Bool {
        return false
    }

// MARK: Private

    func goFullScreen() {
        webViewTopAnchorConstraint?.constant = 0.0
    }

    func shouldShowError(error: NSError) -> Bool {
        return error.code > 600 || error.code < 200
    }

    func layout() {
        webView?.layoutIfNeeded()

        barView?.layoutIfNeeded()
    }

    func setupWebUI() {
        webView?.autoresizesSubviews = true

        webView?.allowsLinkPreview = false
        webView?.isOpaque = false
        webView?.backgroundColor = UIColor.clear
        webView?.isUserInteractionEnabled = true
        webView?.scrollView.bounces = false
        webView?.scrollView.bouncesZoom = false
    }

    func setupBarView() {
        let barView = Bundle.main.loadNibNamed("BarView", owner: self, options: nil)?.first as? BarView
        barView?.translatesAutoresizingMaskIntoConstraints = false
        if let aView = barView {
            webView?.superview?.addSubview(aView)
        }

        guard let barTopAnchor = barView?.superview?.topAnchor else { return }
        guard let barRightAnchor = barView?.superview?.rightAnchor else { return }
        guard let barLeftAnchor = barView?.superview?.leftAnchor else { return }
        let topAnchorConstraint: NSLayoutConstraint? = barView?.topAnchor.constraint(equalTo: barTopAnchor)
        topAnchorConstraint?.isActive = true
        self.barViewTopAnchorConstraint = topAnchorConstraint

        barView?.leftAnchor.constraint(equalTo: barLeftAnchor).isActive = true
        barView?.rightAnchor.constraint(equalTo: barRightAnchor).isActive = true
        let barViewHeightAnchorConstraint: NSLayoutConstraint? = barView?.heightAnchor.constraint(equalToConstant: CGFloat(Constant.urlBarHeight()))
        self.barViewHeightAnchorConstraint = barViewHeightAnchorConstraint
        barViewHeightAnchorConstraint?.isActive = true

        self.barView = barView

        weak var blockSelf: WebController? = self
        weak var blockBar: BarView? = barView

        barView?.backActionBlock = { sender in
            if blockSelf?.webView?.canGoBack ?? false {
                blockSelf?.webView?.goBack()
            } else {
                blockBar?.setBackEnabled(false)
            }
        }

        barView?.forwardActionBlock = { sender in
            if blockSelf?.webView?.canGoForward ?? false {
                blockSelf?.webView?.goForward()
            } else {
                blockBar?.setForwardEnabled(false)
            }
        }

        barView?.homeActionBlock = { sender in
            self.goHome()
        }

        barView?.cancelActionBlock = { sender in
            blockSelf?.webView?.stopLoading()
        }

        barView?.reloadActionBlock = { sender in
            blockSelf?.loadURL?(blockBar?.urlFieldText())
        }

        barView?.goActionBlock = { url in
            blockSelf?.loadURL(url)
        }

        barView?.debugButtonToggledAction = { selected in
            if blockSelf?.onDebugButtonToggled != nil {
                blockSelf?.onDebugButtonToggled?(selected)
            }
        }

        barView?.settingsActionBlock = {
            if blockSelf?.onSettingsButtonTapped != nil {
                blockSelf?.onSettingsButtonTapped?()
            }
        }

        barView?.restartTrackingActionBlock = {
            if blockSelf?.onResetTrackingButtonTapped != nil {
                blockSelf?.onResetTrackingButtonTapped?()
            }
        }

        barView?.switchCameraActionBlock = {
            if blockSelf?.onSwitchCameraButtonTapped != nil {
                blockSelf?.onSwitchCameraButtonTapped?()
            }
        }
    }

    func setupWebContent() {
        contentController?.add(self, name: WEB_AR_INIT_MESSAGE)
        contentController?.add(self, name: WEB_AR_START_WATCH_MESSAGE)
        contentController?.add(self, name: WEB_AR_STOP_WATCH_MESSAGE)
        contentController?.add(self, name: WEB_AR_ON_JS_UPDATE_MESSAGE)
        contentController?.add(self, name: WEB_AR_LOAD_URL_MESSAGE)
        contentController?.add(self, name: WEB_AR_SET_UI_MESSAGE)
        contentController?.add(self, name: WEB_AR_HIT_TEST_MESSAGE)
        contentController?.add(self, name: WEB_AR_ADD_ANCHOR_MESSAGE)
        contentController?.add(self, name: WEB_AR_REQUEST_CV_DATA_MESSAGE)
        contentController?.add(self, name: WEB_AR_START_SENDING_CV_DATA_MESSAGE)
        contentController?.add(self, name: WEB_AR_STOP_SENDING_CV_DATA_MESSAGE)
        contentController?.add(self, name: WEB_AR_REMOVE_ANCHORS_MESSAGE)
        contentController?.add(self, name: WEB_AR_ADD_IMAGE_ANCHOR_MESSAGE)
        contentController?.add(self, name: WEB_AR_CREATE_IMAGE_ANCHOR_MESSAGE)
        contentController?.add(self, name: WEB_AR_ACTIVATE_DETECTION_IMAGE_MESSAGE)
        contentController?.add(self, name: WEB_AR_DEACTIVATE_DETECTION_IMAGE_MESSAGE)
        contentController?.add(self, name: WEB_AR_DESTROY_DETECTION_IMAGE_MESSAGE)
        contentController?.add(self, name: WEB_AR_GET_WORLD_MAP_MESSAGE)
        contentController?.add(self, name: WEB_AR_SET_WORLD_MAP_MESSAGE)
    }

    func cleanWebContent() {
        contentController?.removeScriptMessageHandler(forName: WEB_AR_INIT_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_START_WATCH_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_STOP_WATCH_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_ON_JS_UPDATE_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_LOAD_URL_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_SET_UI_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_HIT_TEST_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_ADD_ANCHOR_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_REQUEST_CV_DATA_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_START_SENDING_CV_DATA_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_STOP_SENDING_CV_DATA_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_REMOVE_ANCHORS_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_ADD_IMAGE_ANCHOR_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_CREATE_IMAGE_ANCHOR_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_ACTIVATE_DETECTION_IMAGE_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_DEACTIVATE_DETECTION_IMAGE_MESSAGE)
        contentController?.removeScriptMessageHandler(forName: WEB_AR_DESTROY_DETECTION_IMAGE_MESSAGE)
    }

    func setupWebView(withRootView rootView: UIView?) {
        let conf = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        let standardUserDefaults = UserDefaults.standard
        // Check if we are supposed to be exposing WebXR.
        if standardUserDefaults.bool(forKey: Constant.exposeWebXRAPIKey()) {
            let scriptBundle = Bundle(for: WebController.self)
            let scriptURL = scriptBundle.path(forResource: "webxr", ofType: "js")
            let scriptContent = try? String(contentsOfFile: scriptURL ?? "", encoding: .utf8)

            print(String(format: "size of webxr.js: %ld", scriptContent?.count ?? 0))

            let userScript = WKUserScript(source: scriptContent ?? "", injectionTime: .atDocumentStart, forMainFrameOnly: true)

            contentController.addUserScript(userScript)
        }
        conf.userContentController = contentController
        self.contentController = contentController

        let pref = WKPreferences()
        pref.javaScriptEnabled = true
        conf.preferences = pref

        conf.processPool = WKProcessPool()

        conf.allowsInlineMediaPlayback = true
        conf.allowsAirPlayForMediaPlayback = true
        conf.allowsPictureInPictureMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: rootView?.bounds ?? CGRect.zero, configuration: conf)
        rootView?.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false

        guard let rootTopAnchor = rootView?.topAnchor else { return }
        guard let rootBottomAnchor = rootView?.bottomAnchor else { return }
        guard let rootLeftAnchor = rootView?.leftAnchor else { return }
        guard let rootRightAnchor = rootView?.rightAnchor else { return }
        
        let webViewTopAnchorConstraint: NSLayoutConstraint = wv.topAnchor.constraint(equalTo: rootTopAnchor)
        self.webViewTopAnchorConstraint = webViewTopAnchorConstraint
        webViewTopAnchorConstraint.isActive = true
        let webViewLeftAnchorConstraint: NSLayoutConstraint = wv.leftAnchor.constraint(equalTo: rootLeftAnchor)
        self.webViewLeftAnchorConstraint = webViewLeftAnchorConstraint
        webViewLeftAnchorConstraint.isActive = true
        let webViewRightAnchorConstraint: NSLayoutConstraint = wv.rightAnchor.constraint(equalTo: rootRightAnchor)
        self.webViewRightAnchorConstraint = webViewRightAnchorConstraint
        webViewRightAnchorConstraint.isActive = true

        wv.bottomAnchor.constraint(equalTo: rootBottomAnchor).isActive = true

        wv.scrollView.contentInsetAdjustmentBehavior = .never

        wv.navigationDelegate = self
        wv.uiDelegate = self
        self.webView = wv
    }

    func documentDidBecomeInteractive() {
        print("documentDidBecomeInteractive")
        let loadedURL = webView?.url?.absoluteString
        self.lastURL = loadedURL ?? ""

        UserDefaults.standard.set(loadedURL, forKey: LAST_URL_KEY)

        onFinishLoad?()

        barView?.finishLoading(webView?.url?.absoluteString)
        barView?.setBackEnabled(webView?.canGoBack ?? false)
        barView?.setForwardEnabled(webView?.canGoForward ?? false)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        weak var blockSelf: WebController? = self

        if (keyPath == "estimatedProgress") && (object as? WKWebView) == blockSelf?.webView {
            blockSelf?.webView?.evaluateJavaScript("document.readyState", completionHandler: { readyState, error in
                DispatchQueue.main.async(execute: {
                    print("Estimated progress: \(blockSelf?.webView?.estimatedProgress ?? 0.0)")
                    print("document.readyState: \(readyState ?? "")")

                    if ((readyState as? String == "interactive") && !(blockSelf?.documentReadyState == "interactive")) || ((blockSelf?.webView?.estimatedProgress ?? 0.0) >= 1.0) {
                        if blockSelf?.webView?.observationInfo != nil {
                            if let aSelf = blockSelf {
                                blockSelf?.webView?.removeObserver(aSelf as NSObject, forKeyPath: "estimatedProgress")
                            }
                            blockSelf?.documentDidBecomeInteractive()
                        } else {
                            print("No Observers Found on WebView in WebController Override observeValue Check")
                        }
                    }

                    blockSelf?.documentReadyState = readyState as? String ?? ""
                })
            })
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}

@inline(__always) private func debugCompletion(name: String?) -> WebCompletion {
    return { param, error in
        if error == nil {
            DDLogDebug("\(String(describing: name)) : success")
        } else {
            DDLogDebug("\(String(describing: name)) : error")
        }
    }
}