import Capacitor
import CapApp_SPM

/**
 * npm 패키지가 아닌 로컬 커스텀 플러그인(OnDeviceSTTPlugin)은 Capacitor가
 * 자동으로 발견하지 못한다 — capacitorDidLoad()에서 수동 등록해야 한다.
 */
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(OnDeviceSTTPlugin())
    }
}
