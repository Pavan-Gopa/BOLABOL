/**
 * Local user profile (prep for Google / password auth + cloud DB).
 * Avatar stored as data URL in localStorage — keep under ~400KB.
 */

export type AuthProvider = 'guest' | 'local' | 'google';

export interface UserProfile {
  displayName: string;
  email: string;
  /** data:image/... or empty */
  avatarDataUrl: string;
  authProvider: AuthProvider;
  /** stub: future backend user id */
  userId: string | null;
  updatedAt: number;
}

const KEY = 'mandalaUserProfile';
const MAX_AVATAR_BYTES = 380_000;

const DEFAULTS: UserProfile = {
  displayName: 'Creator',
  email: '',
  avatarDataUrl: '',
  authProvider: 'guest',
  userId: null,
  updatedAt: 0
};

export function loadUserProfile(): UserProfile {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULTS };
    const parsed = JSON.parse(raw) as Partial<UserProfile>;
    return {
      ...DEFAULTS,
      ...parsed,
      displayName: (parsed.displayName || DEFAULTS.displayName).slice(0, 48),
      email: (parsed.email || '').slice(0, 120),
      avatarDataUrl: typeof parsed.avatarDataUrl === 'string' ? parsed.avatarDataUrl : '',
      authProvider:
        parsed.authProvider === 'local' ||
        parsed.authProvider === 'google' ||
        parsed.authProvider === 'guest'
          ? parsed.authProvider
          : 'guest'
    };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveUserProfile(profile: UserProfile): void {
  const next = { ...profile, updatedAt: Date.now() };
  localStorage.setItem(KEY, JSON.stringify(next));
  window.dispatchEvent(new CustomEvent('mandala-profile-changed', { detail: next }));
}

export function updateUserProfile(partial: Partial<UserProfile>): UserProfile {
  const next = { ...loadUserProfile(), ...partial };
  saveUserProfile(next);
  return next;
}

/**
 * Read image file → square-ish JPEG/PNG data URL under size budget.
 */
export function fileToAvatarDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    if (!file.type.startsWith('image/')) {
      reject(new Error('Please choose an image file'));
      return;
    }
    if (file.size > 8 * 1024 * 1024) {
      reject(new Error('Image must be under 8 MB'));
      return;
    }

    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Failed to read file'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('Invalid image'));
      img.onload = () => {
        const maxSide = 256;
        const scale = Math.min(1, maxSide / Math.max(img.width, img.height));
        const w = Math.max(1, Math.round(img.width * scale));
        const h = Math.max(1, Math.round(img.height * scale));
        const canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
          reject(new Error('Canvas unavailable'));
          return;
        }
        ctx.drawImage(img, 0, 0, w, h);

        let quality = 0.88;
        let dataUrl = canvas.toDataURL('image/jpeg', quality);
        while (dataUrl.length > MAX_AVATAR_BYTES && quality > 0.4) {
          quality -= 0.1;
          dataUrl = canvas.toDataURL('image/jpeg', quality);
        }
        if (dataUrl.length > MAX_AVATAR_BYTES) {
          reject(new Error('Could not compress avatar enough'));
          return;
        }
        resolve(dataUrl);
      };
      img.src = reader.result as string;
    };
    reader.readAsDataURL(file);
  });
}
