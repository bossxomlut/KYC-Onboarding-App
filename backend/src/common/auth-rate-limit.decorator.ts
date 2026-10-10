import { SetMetadata } from "@nestjs/common";

export const AUTH_RATE_LIMIT = Symbol("AUTH_RATE_LIMIT");
/** Bind the policy to the controller, independent of URL casing/aliases. */
export const AuthRateLimit = () => SetMetadata(AUTH_RATE_LIMIT, true);
