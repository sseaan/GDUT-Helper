/**
 * 稳定的 64 位内容指纹（两路 FNV-1a 变体拼接）。
 *
 * 只用于 CalDAV 的资源命名与「内容是否变化」判断，不做安全用途；
 * 同步执行、无依赖，避免为了一个文件名去跑异步摘要。
 */
export function stableHash(input: string): string {
  let forward: number = 0x811c9dc5;
  let salted: number = 0x01000193;
  for (let index = 0; index < input.length; index++) {
    const code: number = input.charCodeAt(index);
    forward = (forward ^ code) >>> 0;
    forward = Math.imul(forward, 16777619) >>> 0;
    salted = (salted ^ code) >>> 0;
    salted = (Math.imul(salted, 2246822519) + index) >>> 0;
  }
  return `${forward.toString(16).padStart(8, '0')}${salted.toString(16).padStart(8, '0')}`;
}
