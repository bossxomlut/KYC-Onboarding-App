import { z } from "zod";

const email = z.string().trim().toLowerCase().max(254).email();
const password = z
  .string()
  .min(12)
  .max(128)
  .refine(
    (value) => /[a-z]/.test(value) && /[A-Z]/.test(value) && /\d/.test(value),
    {
      message:
        "Use at least 12 characters with upper-case, lower-case and a number.",
    },
  );

/** Strict schemas reject unknown fields and normalize emails at the HTTP boundary. */
export const registerSchema = z.strictObject({ email, password });
export const loginSchema = z.strictObject({
  email,
  password: z.string().min(1).max(128),
});
export const emailSchema = z.strictObject({ email });
export const verifyEmailSchema = z.strictObject({
  email,
  code: z.string().regex(/^\d{6}$/),
});
export const refreshSchema = z.strictObject({
  refreshToken: z.string().min(1).max(256),
});
export const resetPasswordSchema = z.strictObject({
  email,
  code: z.string().regex(/^\d{6}$/),
  newPassword: password,
});

export class RegisterDto {
  email!: string;
  password!: string;
}
export class LoginDto {
  email!: string;
  password!: string;
}
export class EmailDto {
  email!: string;
}
export class VerifyEmailDto {
  email!: string;
  code!: string;
}
export class RefreshDto {
  refreshToken!: string;
}
export class ResetPasswordDto {
  email!: string;
  code!: string;
  newPassword!: string;
}
