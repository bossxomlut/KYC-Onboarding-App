/** Explicit injection tokens keep infrastructure contracts independent of HTTP. */
export const APP_CONFIG = Symbol("APP_CONFIG");
export const DATABASE_POOL = Symbol("DATABASE_POOL");
export const MAILER = Symbol("MAILER");
