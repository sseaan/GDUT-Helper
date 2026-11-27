/**
 * ForEach 键值工具。
 *
 * ArkUI 的 ForEach 只按 key 做 diff：key 不变就复用旧节点，即使数据对象已经换了。
 * 所以凡是“同一实体、内容会变”的列表（课程、日程），key 必须带上影响渲染的字段，
 * 否则改教室、改教师、改上课时间后列表不会刷新。
 */
export function hashText(text: string): number {
  let hash: number = 0;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) | 0;
  }
  return hash;
}

/** 把多个字段拼成内容指纹，空值用 `-` 占位，避免拼接歧义。 */
export function contentSignature(parts: string[]): number {
  return hashText(parts.map((part: string) => part.length > 0 ? part : '-').join('\u0001'));
}
