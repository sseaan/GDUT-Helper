import { BlurStrategy, ScrollEffectType } from '@kit.UIDesignKit';
import { ImmersiveMaterial } from './ImmersiveMaterial';

/**
 * HDS immersive title bar options.
 *
 * A GRADIENT_BLUR scroll effect plus system material makes content scrolling under
 * the title bar progressively blur instead of showing through sharply. The material
 * type is gated by hdsMaterial support, so devices without IMMERSIVE degrade to
 * ADAPTIVE rather than requesting an unsupported effect.
 */
export function immersiveTitleBar(
  mainTitle: ResourceStr,
  actions: Record<string, Object>[] = []
): Record<string, Object> {
  const title: Record<string, Object> = { 'mainTitle': mainTitle };
  const content: Record<string, Object> = { 'title': title };
  if (actions.length > 0) {
    const menu: Record<string, Object> = {
      'value': actions,
      'maxCount': actions.length
    };
    content['menu'] = menu;
  }

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
