import { common } from '@kit.AbilityKit';
import { asset } from '@kit.AssetStoreKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CalDavConfig, emptyCalDavConfig } from './CalDavModels';

const STORE_NAME: string = 'caldav_settings';
const ASSET_ALIAS: string = 'gdut_helper_caldav_password';
const KEY_URL: string = 'url';
const KEY_USER: string = 'username';
const KEY_ENABLED: string = 'enabled';
const KEY_ETAG: string = 'lastEtag';
const KEY_PUSHED_AT: string = 'lastPushedAt';
const KEY_EVENT_COUNT: string = 'lastEventCount';

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function aliasBytes(): Uint8Array {
  return encode(ASSET_ALIAS);
}

function assetQuery(): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, aliasBytes());
  return query;
}

/**
 * CalDAV 配置读写。
 *
 * 服务器地址、用户名、开关和推送状态放 Preferences；密码只进系统 Asset Store，
 * 与统一认证、体测账号一致，不写日志、不进备份。
 */
export class CalDavSettings {
  static async load(context: common.Context): Promise<CalDavConfig> {
    const config: CalDavConfig = emptyCalDavConfig();
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const url = await store.get(KEY_URL, '');
      const user = await store.get(KEY_USER, '');
      const enabled = await store.get(KEY_ENABLED, false);
      const etag = await store.get(KEY_ETAG, '');
      const pushedAt = await store.get(KEY_PUSHED_AT, 0);
      const count = await store.get(KEY_EVENT_COUNT, 0);
      config.url = typeof url === 'string' ? url : '';
      config.username = typeof user === 'string' ? user : '';
      config.enabled = enabled === true;
      config.lastEtag = typeof etag === 'string' ? etag : '';
      config.lastPushedAt = typeof pushedAt === 'number' ? pushedAt : 0;
      config.lastEventCount = typeof count === 'number' ? count : 0;
    } catch (error) {
      return config;
    }
    return config;
  }

  static async save(context: common.Context, config: CalDavConfig): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_URL, config.url);
    await store.put(KEY_USER, config.username);
    await store.put(KEY_ENABLED, config.enabled);
    await store.put(KEY_ETAG, config.lastEtag);
    await store.put(KEY_PUSHED_AT, config.lastPushedAt);
    await store.put(KEY_EVENT_COUNT, config.lastEventCount);
    await store.flush();
  }

  /** 密码是可选能力：Radicale 关掉认证时不填也能推。 */
  static async savePassword(password: string): Promise<void> {
    await CalDavSettings.clearPassword();
    if (password.length === 0) {
      return;
    }
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, aliasBytes());
    attributes.set(asset.Tag.SECRET, encode(password));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attributes);
  }

  static async password(): Promise<string> {
    try {
      const query: asset.AssetMap = assetQuery();
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const results = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const stored = results[0].get(asset.Tag.SECRET);
      if (!(stored instanceof Uint8Array)) {
        return '';
      }
      return new util.TextDecoder('utf-8').decodeToString(stored);
    } catch (error) {
      return '';
    }
  }

  static async clearPassword(): Promise<void> {
    try {
      await asset.remove(assetQuery());
    } catch (error) {
      // 没有保存过密码属于正常状态。
    }
  }
}
