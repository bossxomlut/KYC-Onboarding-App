import { z } from "zod";
import { requiredStepSchema } from "../kyc/kyc.schemas.js";

export const reviewUserIdSchema = z.uuid();
export const reviewMediaQuerySchema = z.strictObject({
  submissionId: z.uuid(),
});
export const reviewPaginationSchema = z.strictObject({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).max(1_000_000).default(0),
  status: z
    .enum(["pending_review", "verified", "rejected", "all"])
    .default("pending_review"),
  search: z.string().trim().max(254).optional(),
});

export const reviewDecisionSchema = z
  .strictObject({
    submissionId: z.uuid(),
    decision: z.enum(["verified", "rejected"]),
    reason: z.string().trim().min(3).max(1000).optional(),
    requiredSteps: z.array(requiredStepSchema).max(3).default([]),
  })
  .superRefine((value, context) => {
    if (
      value.decision === "rejected" &&
      (!value.reason || value.requiredSteps.length === 0)
    ) {
      context.addIssue({
        code: "custom",
        message:
          "A rejection requires a reason and at least one required step.",
      });
    }
    if (value.decision === "verified" && value.requiredSteps.length > 0) {
      context.addIssue({
        code: "custom",
        path: ["requiredSteps"],
        message: "An approved profile must not request changes.",
      });
    }
  });

export type ReviewPagination = z.infer<typeof reviewPaginationSchema>;
export type ReviewDecision = z.infer<typeof reviewDecisionSchema>;
