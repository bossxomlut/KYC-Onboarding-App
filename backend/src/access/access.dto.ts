import { z } from "zod";
import { registerSchema } from "../auth/auth.dto.js";

const managedRole = z.enum(["user", "reviewer"]);
const decisionReason = z.string().trim().min(1).max(1000).optional();
export const identifierSchema = z.uuid();
export const paginationSchema = z.strictObject({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).max(100000).default(0),
});
export const requestsPaginationSchema = paginationSchema.extend({
  status: z.enum(["pending", "approved", "rejected"]).default("pending"),
});
export const createAccountSchema = registerSchema.extend({ role: managedRole });
export const changeRoleSchema = z.strictObject({
  role: managedRole,
  reason: decisionReason,
});
export const requestRoleSchema = z.strictObject({
  reason: z.string().trim().min(10).max(1000),
});
export const decideRoleSchema = z.strictObject({
  decision: z.enum(["approved", "rejected"]),
  reason: decisionReason,
});

export type PaginationDto = z.infer<typeof paginationSchema>;
export type RequestsPaginationDto = z.infer<typeof requestsPaginationSchema>;
export type CreateAccountDto = z.infer<typeof createAccountSchema>;
export type ChangeRoleDto = z.infer<typeof changeRoleSchema>;
export type RequestRoleDto = z.infer<typeof requestRoleSchema>;
export type DecideRoleDto = z.infer<typeof decideRoleSchema>;
