import { hdsMaterial } from '@kit.UIDesignKit';
import { AppearanceSettings } from '../state/AppearanceSettings';

/**
 * 沉浸光感 capability + material policy.
 *
 * M1 keeps the policy automatic: use IMMERSIVE when the device reports it, otherwise
 * fall back to ADAPTIVE. Per-level (exquisite/gentle/smooth) user settings can be
 * added in M1 without changing call sites.
 */
export class ImmersiveMaterial {
  static supported(): boolean {
    try {
      const types: hdsMaterial.MaterialType[] = hdsMaterial.getSystemMaterialTypes();
      for (let i = 0; i < types.length; i++) {
        if (types[i] === hdsMaterial.MaterialType.IMMERSIVE) {
          return true;
        }
      }
      return false;
    } catch (error) {
      return false;
    }
  }

  static type(): hdsMaterial.MaterialType {
    return ImmersiveMaterial.supported() && AppearanceSettings.immersiveEnabled()
      ? hdsMaterial.MaterialType.IMMERSIVE
      : hdsMaterial.MaterialType.ADAPTIVE;
  }

  static level(): hdsMaterial.MaterialLevel {
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  static summary(): string {
    if (!ImmersiveMaterial.supported()) {
      return '设备不支持 IMMERSIVE，使用自适应材质';
    }
    return AppearanceSettings.immersiveEnabled()
      ? '沉浸光感已启用（IMMERSIVE）'
      : '沉浸光感已关闭，使用自适应材质';
  }
}
