import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private static let privacyShieldTag = 0x50524956
  private var isObservingCaptureState = false

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if !isObservingCaptureState {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenCaptureStateDidChange),
        name: UIScreen.capturedDidChangeNotification,
        object: nil
      )
      isObservingCaptureState = true
    }
    updatePrivacyShield(for: scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    updatePrivacyShield(for: scene)
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    setPrivacyShield(visible: true, for: scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    setPrivacyShield(visible: true, for: scene)
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    if isObservingCaptureState {
      NotificationCenter.default.removeObserver(
        self,
        name: UIScreen.capturedDidChangeNotification,
        object: nil
      )
      isObservingCaptureState = false
    }
    super.sceneDidDisconnect(scene)
  }

  @objc private func screenCaptureStateDidChange() {
    for scene in UIApplication.shared.connectedScenes {
      updatePrivacyShield(for: scene)
    }
  }

  private func updatePrivacyShield(for scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let shouldHideContent =
      windowScene.activationState != .foregroundActive || windowScene.screen.isCaptured
    setPrivacyShield(visible: shouldHideContent, for: scene)
  }

  private func setPrivacyShield(visible: Bool, for scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    for window in windowScene.windows {
      if visible {
        let shield: UIView
        if let existing = window.viewWithTag(Self.privacyShieldTag) {
          shield = existing
        } else {
          shield = UIView(frame: window.bounds)
          shield.tag = Self.privacyShieldTag
          shield.backgroundColor = .black
          shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          shield.isUserInteractionEnabled = false
          shield.accessibilityElementsHidden = true
          window.addSubview(shield)
        }
        window.bringSubviewToFront(shield)
      } else {
        window.viewWithTag(Self.privacyShieldTag)?.removeFromSuperview()
      }
    }
  }

}
