export interface PaletteColor {
  background: string;
  foreground: string;
}

const PALETTE: PaletteColor[] = [
  { background: '#F3EBDD', foreground: '#6C5937' },
  { background: '#DCEFE2', foreground: '#2D694F' },
  { background: '#E5E2F5', foreground: '#514C87' },
  { background: '#DCEBF5', foreground: '#315F7E' },
  { background: '#F6DEE5', foreground: '#8F3E5A' },
  { background: '#F5EFCA', foreground: '#75641F' },
  { background: '#D9EFEC', foreground: '#2C6E69' },
  { background: '#F8E3D2', foreground: '#8A5031' },
  { background: '#E2F0D9', foreground: '#4A6A31' },
  { background: '#E2E8F1', foreground: '#455A79' },
  { background: '#F3DEEF', foreground: '#7A3D6E' },
  { background: '#ECE8D7', foreground: '#695B32' }
];

export class CoursePalette {
  static readonly SIZE: number = PALETTE.length;
  static readonly PAST_BACKGROUND: string = '#ECEFF1';
  static readonly PAST_FOREGROUND: string = '#9AA1A8';

  static get(colorKey: number): PaletteColor {
    const index: number = ((colorKey % PALETTE.length) + PALETTE.length) % PALETTE.length;
    return PALETTE[index];
  }

  static background(colorKey: number): string {
    return CoursePalette.get(colorKey).background;
  }

  static foreground(colorKey: number): string {
    return CoursePalette.get(colorKey).foreground;
  }
}
