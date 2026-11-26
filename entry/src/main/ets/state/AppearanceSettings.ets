import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { THEME_COLOR_KEY, ThemeColor } from '../common/ThemeColor';

const STORE_NAME: string = 'appearance_settings';
const MODE_KEY: string = 'themeMode';
export const IMMERSIVE_KEY: string = 'immersiveEnabled';
export const HANDEDNESS_KEY: string = 'handednessEnabled';
export const MATERIAL_LEVEL_KEY: string = 'materialLevel';

export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

export class AppearanceSettings {
  static async load(context: common.UIAbilityContext): Promise<ThemeMode> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const value = await store.get(MODE_KEY, ThemeMode.SYSTEM);
      const immersive = await store.get(IMMERSIVE_KEY, true);
      const handedness = await store.get(HANDEDNESS_KEY, true);
      const themeColor = await store.get(THEME_COLOR_KEY, ThemeColor.DEFAULT);
      const materialLevel = await store.get(MATERIAL_LEVEL_KEY, 10);
      const level: number = typeof materialLevel === 'number' ? materialLevel : 10;
      AppStorage.setOrCreate(IMMERSIVE_KEY, immersive === true);
      AppStorage.setOrCreate(HANDEDNESS_KEY, handedness === true);
      AppStorage.setOrCreate(MATERIAL_LEVEL_KEY, level === 0 || level === 1 || level === 2 ? level : 10);
      AppStorage.setOrCreate(THEME_COLOR_KEY, ThemeColor.normalize(themeColor as string));
      if (value === ThemeMode.LIGHT) {
        return ThemeMode.LIGHT;
      }
      if (value === ThemeMode.DARK) {
        return ThemeMode.DARK;
      }
    } catch (error) {
      AppStorage.setOrCreate(IMMERSIVE_KEY, true);
      AppStorage.setOrCreate(HANDEDNESS_KEY, true);
      AppStorage.setOrCreate(MATERIAL_LEVEL_KEY, 10);
      AppStorage.setOrCreate(THEME_COLOR_KEY, ThemeColor.DEFAULT);
    }
    return ThemeMode.SYSTEM;
  }

  static immersiveEnabled(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(IMMERSIVE_KEY);
    return value === undefined ? true : value;
  }

  static handednessEnabled(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(HANDEDNESS_KEY);
    return value === undefined ? true : value;
  }

  static themeColorId(): string {
    return ThemeColor.normalize(AppStorage.get<string>(THEME_COLOR_KEY));
  }

  static materialLevel(): number {
    const value: number | undefined = AppStorage.get<number>(MATERIAL_LEVEL_KEY);
    return value === 0 || value === 1 || value === 2 ? value : 10;
  }

  static themeColor(): string {
    return ThemeColor.current();
  }

  static async setImmersive(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate(IMMERSIVE_KEY, enabled);
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(IMMERSIVE_KEY, enabled);
      await store.flush();
    } catch (error) {
      // The in-memory selection still applies for this session.
    }
  }

  static async setMaterialLevel(context: common.UIAbilityContext, level: number): Promise<void> {
    const normalized: number = level === 0 || level === 1 || level === 2 ? level : 10;
    AppStorage.setOrCreate(MATERIAL_LEVEL_KEY, normalized);
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(MATERIAL_LEVEL_KEY, normalized);
      await store.flush();
    } catch (error) {
      // The in-memory selection still applies for this session.
    }
  }

  static async setThemeColor(context: common.UIAbilityContext, id: string): Promise<void> {
    const normalized: string = ThemeColor.normalize(id);
    AppStorage.setOrCreate(THEME_COLOR_KEY, normalized);
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(THEME_COLOR_KEY, normalized);
      await store.flush();
    } catch (error) {
      // The in-memory selection still applies for this session.
    }
  }

  static async setHandedness(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate(HANDEDNESS_KEY, enabled);
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(HANDEDNESS_KEY, enabled);
      await store.flush();
    } catch (error) {
      // The in-memory selection still applies for this session.
    }
  }

  static apply(context: common.UIAbilityContext, mode: ThemeMode): void {
    let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === ThemeMode.LIGHT) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === ThemeMode.DARK) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      context.getApplicationContext().setColorMode(colorMode);
    } catch (error) {
      // Older devices may not support runtime color mode changes.
    }
  }

  static async set(context: common.UIAbilityContext, mode: ThemeMode): Promise<void> {
    AppearanceSettings.apply(context, mode);
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(MODE_KEY, mode);
      await store.flush();
    } catch (error) {
      // The in-memory selection still applies for this session.
    }
  }
}
