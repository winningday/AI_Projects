// Module: Shared types for the Verbalize API

export interface Env {
  DB: D1Database;
  JWT_SECRET: string;
  ENVIRONMENT: string;
}

export interface JWTPayload {
  sub: string; // user ID
  email: string;
  iat: number;
  exp: number;
}

export interface AuthedEnv extends Env {
  userId: string;
  userEmail: string;
}

// Request/response types

export interface RegisterRequest {
  email: string;
  password: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RefreshRequest {
  refresh_token: string;
}

export interface SettingsPayload {
  defaultStyleTone?: string;
  styleProfiles?: Record<string, string>;
  smartFormatting?: boolean;
  translationEnabled?: boolean;
  targetLanguage?: string;
  autoAddToDictionary?: boolean;
  playSoundEffects?: boolean;
  typingSpeed?: number;
}

export interface DictionaryEntryPayload {
  id: string;
  word: string;
  auto_added: boolean;
  date_added: string;
}

export interface CorrectionPayload {
  id: string;
  original: string;
  corrected: string;
  date: string;
}

export interface TranscriptPayload {
  id: string;
  original_text: string | null;
  cleaned_text: string | null;
  corrected_text: string | null;
  duration_seconds: number | null;
  device_source: string | null;
  timestamp: string;
}
