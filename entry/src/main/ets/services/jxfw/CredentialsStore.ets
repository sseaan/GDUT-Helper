import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS: string = 'gdut_helper_jxfw_account';

export interface SavedCredentials {
  username: string;
  password: string;
}

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function aliasBytes(): Uint8Array {
  return encode(ALIAS);
}

function queryMap(): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, aliasBytes());
  return query;
}

/** Stores the jxfw account only in the system Asset Store (device first unlocked). */
export class CredentialsStore {
  static async save(username: string, password: string): Promise<void> {
    await CredentialsStore.clear();
    const value: SavedCredentials = { username: username, password: password };
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, aliasBytes());
    attributes.set(asset.Tag.SECRET, encode(JSON.stringify(value)));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attributes);
  }

  static async load(): Promise<SavedCredentials | null> {
    try {
      const query: asset.AssetMap = queryMap();
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const results = await asset.query(query);
      if (results.length === 0) {
        return null;
      }
      const stored = results[0].get(asset.Tag.SECRET);
      if (!(stored instanceof Uint8Array)) {
        return null;
      }
      const text: string = new util.TextDecoder('utf-8').decodeToString(stored);
      const parsed: SavedCredentials = JSON.parse(text) as SavedCredentials;
      if (parsed.username.length === 0 || parsed.password.length === 0) {
        return null;
      }
      return parsed;
    } catch (error) {
      return null;
    }
  }

  static async clear(): Promise<void> {
    try {
      await asset.remove(queryMap());
    } catch (error) {
      // No saved account is a normal logout state.
    }
  }
}
