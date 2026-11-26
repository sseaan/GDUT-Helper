export const THEME_COLOR_KEY: string = 'themeColorId';

export enum ThemeColorId {
  HARMONY = 'harmony',
  GDUT = 'gdut',
  GOKE = 'goke'
}

export interface ThemeColorOption {
  id: string;
  name: string;
  detail: string;
  value: string;
}

/** User-selectable accent colors. Keep values as plain hex so alpha variants are easy to derive. */
export class ThemeColor {
  static readonly DEFAULT: string = ThemeColorId.HARMONY;
  static readonly HARMONY_BLUE: string = '#0A59F7';
  static readonly GDUT_RED: string = '#C8102E';
  static readonly GOKE_MINT: string = '#CDEBE3';

  static readonly OPTIONS: ThemeColorOption[] = [
    {
      id: ThemeColorId.HARMONY,
      name: '鸿蒙蓝',
      detail: '默认',
      value: ThemeColor.HARMONY_BLUE
    },
    {
      id: ThemeColorId.GDUT,
      name: '广工红',
      detail: '校色',
      value: ThemeColor.GDUT_RED
    },
    {
      id: ThemeColorId.GOKE,
      name: 'Goke绿',
      detail: '薄荷绿',
      value: ThemeColor.GOKE_MINT
    }
  ];

  static normalize(id: string | undefined): string {
    if (id === ThemeColorId.GDUT || id === ThemeColorId.GOKE ||
      id === ThemeColorId.HARMONY) {
      return id;
    }
    return ThemeColor.DEFAULT;
  }

  static of(id: string | undefined): string {
    const normalized: string = ThemeColor.normalize(id);
    if (normalized === ThemeColorId.GDUT) {
      return ThemeColor.GDUT_RED;
    }
    if (normalized === ThemeColorId.GOKE) {
      return ThemeColor.GOKE_MINT;
    }
    return ThemeColor.HARMONY_BLUE;
  }

  static current(): string {
    return ThemeColor.of(AppStorage.get<string>(THEME_COLOR_KEY));
  }

  /** Foreground color that stays readable on the accent surface. */
  static onBrand(id: string | undefined): string {
    return ThemeColor.normalize(id) === ThemeColorId.GOKE ? '#182A26' : '#FFFFFF';
  }

  /** Accent color used for text/icons on neutral backgrounds. */
  static text(id: string | undefined): string {
    return ThemeColor.normalize(id) === ThemeColorId.GOKE ? '#176B5A' : ThemeColor.of(id);
  }

  static currentText(): string {
    return ThemeColor.text(AppStorage.get<string>(THEME_COLOR_KEY));
  }

  static nameOf(id: string | undefined): string {
    const normalized: string = ThemeColor.normalize(id);
    for (const option of ThemeColor.OPTIONS) {
      if (option.id === normalized) {
        return option.name;
      }
    }
    return '鸿蒙蓝';
  }

  /** Returns a translucent version of a #RRGGBB accent color. */
  static alpha(color: string, alpha: number): string {
    const hex: string = color.startsWith('#') ? color.substring(1) : color;
    if (hex.length !== 6) {
      return color;
    }
    const r: number = Number.parseInt(hex.substring(0, 2), 16);
    const g: number = Number.parseInt(hex.substring(2, 4), 16);
    const b: number = Number.parseInt(hex.substring(4, 6), 16);
    if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
      return color;
    }
    const a: number = Math.max(0, Math.min(1, alpha));
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  }
}
