import { z } from "zod";

export const submissionIdSchema = z.uuid();
export const historyPaginationSchema = z.strictObject({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).max(1_000_000).default(0),
});
export type HistoryPagination = z.infer<typeof historyPaginationSchema>;
