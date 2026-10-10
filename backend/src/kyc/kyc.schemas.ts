import { z } from "zod";

export const requiredStepSchema = z.enum([
  "personal_details",
  "document",
  "selfie",
]);
export const documentTypeSchema = z.enum([
  "passport",
  "national_id",
  "driving_licence",
]);
export const mediaKindSchema = z.enum(["document", "selfie"]);
export const personalDetailsSchema = z.strictObject({
  fullName: z.string().trim().min(2).max(120),
  dateOfBirth: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .refine(
      (value) => {
        const birthday = new Date(`${value}T00:00:00Z`);
        if (
          Number.isNaN(birthday.getTime()) ||
          birthday.toISOString().slice(0, 10) !== value
        )
          return false;
        const today = new Date();
        const years =
          today.getUTCFullYear() -
          birthday.getUTCFullYear() -
          (today.getUTCMonth() < birthday.getUTCMonth() ||
          (today.getUTCMonth() === birthday.getUTCMonth() &&
            today.getUTCDate() < birthday.getUTCDate())
            ? 1
            : 0);
        return years >= 18 && years <= 120;
      },
      { message: "Enter a valid birth date. Applicants must be 18 or older." },
    ),
  nationality: z.string().trim().min(2).max(80),
  address: z.string().trim().min(8).max(500),
  documentNumber: z
    .string()
    .trim()
    .min(4)
    .max(40)
    .regex(/^[A-Za-z0-9 -]+$/),
});

export const uploadFieldsSchema = z.strictObject({
  documentType: z.unknown().optional(),
  captureId: z
    .string()
    .min(16)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/)
    .optional(),
});

export type PersonalDetails = z.infer<typeof personalDetailsSchema>;
export type MediaKind = z.infer<typeof mediaKindSchema>;
export type UploadFields = z.infer<typeof uploadFieldsSchema>;
export type RequiredStep = z.infer<typeof requiredStepSchema>;
