import { inflateRawSync } from "node:zlib";

/** Reads [length] bytes at [offset] from the archive (a local buffer in tests, a ranged S3 GET in production). */
export type RangeReader = (offset: number, length: number) => Promise<Buffer>;

const EOCD_SIG = 0x06054b50;
const CEN_SIG = 0x02014b50;
const LOC_SIG = 0x04034b50;

export class ApkError extends Error {}

/** Locates AndroidManifest.xml via the zip central directory and returns its (inflated) bytes. */
export async function readManifest(size: number, read: RangeReader): Promise<Buffer> {
  if (size < 22) throw new ApkError("not a zip");
  const tailLen = Math.min(size, 22 + 0xffff);
  const tail = await read(size - tailLen, tailLen);
  let eocd = -1;
  for (let i = tail.length - 22; i >= 0; i--) {
    if (tail.readUInt32LE(i) === EOCD_SIG) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new ApkError("zip end record not found");
  const cdSize = tail.readUInt32LE(eocd + 12);
  const cdOffset = tail.readUInt32LE(eocd + 16);
  if (cdOffset === 0xffffffff || cdSize === 0xffffffff) throw new ApkError("zip64 is not supported");
  if (cdOffset + cdSize > size || cdSize > 16 * 1024 * 1024) throw new ApkError("bad central directory");
  const cd = await read(cdOffset, cdSize);
  let p = 0;
  while (p + 46 <= cd.length && cd.readUInt32LE(p) === CEN_SIG) {
    const method = cd.readUInt16LE(p + 10);
    const csize = cd.readUInt32LE(p + 20);
    const usize = cd.readUInt32LE(p + 24);
    const nlen = cd.readUInt16LE(p + 28);
    const elen = cd.readUInt16LE(p + 30);
    const clen = cd.readUInt16LE(p + 32);
    const lho = cd.readUInt32LE(p + 42);
    const name = cd.subarray(p + 46, p + 46 + nlen).toString("utf8");
    if (name === "AndroidManifest.xml") {
      if (usize > 4 * 1024 * 1024 || csize > 4 * 1024 * 1024) throw new ApkError("manifest too large");
      const lh = await read(lho, 30);
      if (lh.length < 30 || lh.readUInt32LE(0) !== LOC_SIG) throw new ApkError("bad local header");
      const dataStart = lho + 30 + lh.readUInt16LE(26) + lh.readUInt16LE(28);
      const data = await read(dataStart, csize);
      if (method === 0) return data;
      if (method === 8) return inflateRawSync(data);
      throw new ApkError("unsupported manifest compression");
    }
    p += 46 + nlen + elen + clen;
  }
  throw new ApkError("AndroidManifest.xml not found");
}

const RES_XML = 0x0003;
const STRING_POOL = 0x0001;
const START_ELEMENT = 0x0102;
const TYPE_INT_DEC = 0x10;
const TYPE_INT_HEX = 0x11;

/** Reads `versionCode` (and the package name) off the root `<manifest>` element of an Android binary XML document. */
export function parseManifest(buf: Buffer): { versionCode: number; packageName: string | null } {
  if (buf.length < 8 || buf.readUInt16LE(0) !== RES_XML) throw new ApkError("not binary XML");
  const strings: string[] = [];
  let p = buf.readUInt16LE(2); // header size
  const end = Math.min(buf.length, buf.readUInt32LE(4));
  while (p + 8 <= end) {
    const type = buf.readUInt16LE(p);
    const hdr = buf.readUInt16LE(p + 2);
    const size = buf.readUInt32LE(p + 4);
    if (size < 8) break;
    if (type === STRING_POOL) {
      const count = buf.readUInt32LE(p + 8);
      const flags = buf.readUInt32LE(p + 16);
      const stringsStart = buf.readUInt32LE(p + 20);
      const utf8 = (flags & 0x100) !== 0;
      for (let i = 0; i < count; i++) {
        const off = p + stringsStart + buf.readUInt32LE(p + hdr + i * 4);
        strings.push(utf8 ? readUtf8(buf, off) : readUtf16(buf, off));
      }
    } else if (type === START_ELEMENT) {
      // chunk header(16) + ns(4) name(4), then attrStart(2) attrSize(2) attrCount(2)
      const attrStart = buf.readUInt16LE(p + 24);
      const attrSize = buf.readUInt16LE(p + 26);
      const attrCount = buf.readUInt16LE(p + 28);
      let versionCode: number | null = null;
      let pkg: string | null = null;
      for (let i = 0; i < attrCount; i++) {
        const a = p + 16 + attrStart + i * attrSize;
        const nameIdx = buf.readUInt32LE(a + 4);
        const rawIdx = buf.readInt32LE(a + 8);
        const dataType = buf.readUInt8(a + 15);
        const data = buf.readUInt32LE(a + 16);
        const name = strings[nameIdx];
        if (name === "package" && rawIdx >= 0) pkg = strings[rawIdx] ?? null;
        if (name === "versionCode" && (dataType === TYPE_INT_DEC || dataType === TYPE_INT_HEX)) versionCode = data;
      }
      if (versionCode == null) throw new ApkError("versionCode not found");
      return { versionCode, packageName: pkg };
    }
    p += size;
  }
  throw new ApkError("manifest element not found");
}

function readUtf8(buf: Buffer, off: number): string {
  let o = off;
  if (buf[o++] & 0x80) o++; // utf-16 length is two bytes
  let len = buf[o++];
  if (len & 0x80) len = ((len & 0x7f) << 8) | buf[o++];
  return buf.toString("utf8", o, o + len);
}

function readUtf16(buf: Buffer, off: number): string {
  let len = buf.readUInt16LE(off);
  let o = off + 2;
  if (len & 0x8000) {
    len = ((len & 0x7fff) << 16) | buf.readUInt16LE(o);
    o += 2;
  }
  return buf.toString("utf16le", o, o + len * 2);
}

/** versionCode the installed APK must carry for [build] (split-per-abi arm64 scheme: 2000 + N). */
export const expectedVersionCode = (build: number) => 2000 + build;

export async function apkVersionCode(size: number, read: RangeReader): Promise<number> {
  return parseManifest(await readManifest(size, read)).versionCode;
}
