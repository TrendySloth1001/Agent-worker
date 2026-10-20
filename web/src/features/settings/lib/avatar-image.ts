import { AVATAR_MAX } from "../schemas/account";

export const AVATAR_EDGE = 256;
const ACCEPTED = ["image/png", "image/jpeg", "image/webp"];
const QUALITIES = [0.9, 0.8, 0.65, 0.5];

export const isAcceptedImage = (type: string): boolean => ACCEPTED.includes(type);

export const fitWithin = (width: number, height: number, edge: number) => {
  const scale = Math.min(1, edge / Math.max(width, height));
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
};

export const fitsAvatarLimit = (dataUrl: string): boolean => dataUrl.length <= AVATAR_MAX;

export async function fileToAvatar(file: File): Promise<string | null> {
  const bitmap = await createImageBitmap(file);
  const { width, height } = fitWithin(bitmap.width, bitmap.height, AVATAR_EDGE);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d")?.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();
  for (const quality of QUALITIES) {
    const url = canvas.toDataURL("image/jpeg", quality);
    if (fitsAvatarLimit(url)) return url;
  }
  return null;
}
