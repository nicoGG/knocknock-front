import Flutter
import UIKit
import share_handler_ios

class SceneDelegate: FlutterSceneDelegate {
  private func isShare(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "sharemedia-cl.nocknock.app"
  }

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                     options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for item in connectionOptions.urlContexts where isShare(item.url) {
      _ = SwiftShareHandlerIosPlatform.instance.application(
        UIApplication.shared, didFinishLaunchingWithOptions: [UIApplication.LaunchOptionsKey.url: item.url])
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for item in URLContexts where isShare(item.url) {
      _ = SwiftShareHandlerIosPlatform.instance.application(UIApplication.shared, open: item.url)
    }
    let remaining = Set(URLContexts.filter { !isShare($0.url) })
    if !remaining.isEmpty { super.scene(scene, openURLContexts: remaining) }
  }
}
