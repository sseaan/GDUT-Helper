import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS: string = 'gdut_helper_tzcs_account';

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

export interface TzcsCredentials {
  username: string;
  password: string;
}

export class TzcsCredentialsStore {
  static async save(username: string, password: string): Promise<void> {
    await TzcsCredentialsStore.clear();
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, encode(ALIAS));
    attributes.set(asset.Tag.SECRET, encode(JSON.stringify({ username: username, password: password })));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attributes);
  }

  static async load(): Promise<TzcsCredentials | null> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, encode(ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const results = await asset.query(query);
      if (results.length === 0) {
        return null;
      }
      const stored = results[0].get(asset.Tag.SECRET);
      if (!(stored instanceof Uint8Array)) {
        return null;
      }
      return JSON.parse(new util.TextDecoder('utf-8').decodeToString(stored)) as TzcsCredentials;
    } catch (error) {
      return null;
    }
  }

  static async clear(): Promise<void> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, encode(ALIAS));
      await asset.remove(query);
    } catch (error) {
      // No saved credentials is a normal state.
    }
  }
}
