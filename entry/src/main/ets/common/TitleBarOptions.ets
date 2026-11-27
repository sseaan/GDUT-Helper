import { BlurStrategy, ScrollEffectType } from '@kit.UIDesignKit';
import { ImmersiveMaterial } from './ImmersiveMaterial';

/**
 * HDS immersive title bar options.
 *
 * A GRADIENT_BLUR scroll effect plus system material makes content scrolling under
 * the title bar progressively blur instead of showing through sharply. The material
 * type is gated by hdsMaterial support, so devices without IMMERSIVE degrade to
 * ADAPTIVE rather than requesting an unsupported effect.
 *
 * `menu` is always sent, even with an empty `value`: HDS applies title bar options
 * partially, so omitting `menu` keeps the previous tab's actions and the icon leaks
 * onto pages that never asked for it.
 */
export function immersiveTitleBar(
  mainTitle: ResourceStr,
  actions: Record<string, Object>[] = []
): Record<string, Object> {
  const title: Record<string, Object> = { 'mainTitle': mainTitle };
  const menu: Record<string, Object> = {
    'value': actions,
    'maxCount': actions.length > 0 ? actions.length : 1
  };
  const content: Record<string, Object> = {
    'title': title,
    'menu': menu
  };

  const material: Record<string, Object> = {
    'materialType': ImmersiveMaterial.type(),
    'materialLevel': ImmersiveMaterial.level()
  };
  const scroll: Record<string, Object> = {
    'enableScrollEffect': true,
    'scrollEffectType': ScrollEffectType.GRADIENT_BLUR
  };
  const style: Record<string, Object> = {
    'blurStrategy': BlurStrategy.ENABLE,
    'systemMaterialEffect': material,
    'scrollEffectOpts': scroll
  };

  return {
    'avoidLayoutSafeArea': true,
    'enableComponentSafeArea': false,
    'content': content,
    'style': style
  };
}

/** One native HDS title-bar action. */
export function titleBarAction(
  label: ResourceStr,
  icon: Resource,
  action: () => void
): Record<string, Object> {
  const item: Record<string, Object> = {
    'label': label,
    'icon': icon,
    'isEnabled': true,
    'action': action
  };
  return { 'content': item };
}
