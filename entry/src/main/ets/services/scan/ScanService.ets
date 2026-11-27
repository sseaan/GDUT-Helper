import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { ScanPayload, ScanRoute } from './ScanRoute';

const SCAN_CANCELLED: number = 1000500002;
const SCAN_INTERNAL_ERROR: number = 1000500001;

/** Scan failures that the caller should surface to the user. */
export class ScanError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/**
 * Wrapper around Scan Kit's default scanning UI.
 *
 * The default UI runs in a system-owned page, so the app requests no camera
 * permission and never touches camera frames; scanning is also unavailable on
 * devices without the ScanBarcode syscap (for example most emulators).
 */
export class ScanService {
  static isSupported(): boolean {
    try {
      return canIUse('SystemCapability.Multimedia.Scan.ScanBarcode');
    } catch (error) {
      return false;
    }
  }

  /** Opens the scanner and returns the classified payload, or null when cancelled. */
  static async scan(context: common.UIAbilityContext): Promise<ScanPayload | null> {
    if (!ScanService.isSupported()) {
      throw new ScanError('当前设备不支持扫码');
    }
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableAlbum: true,
      enableMultiMode: false
    };
    try {
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
      return ScanRoute.classify(result.originalValue);
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      if (failure.code === SCAN_CANCELLED) {
        return null;
      }
      if (failure.code === SCAN_INTERNAL_ERROR || failure.code === 401) {
        throw new ScanError('扫码失败，请重试');
      }
      throw new ScanError('扫码失败，请重试');
    }
  }
}
