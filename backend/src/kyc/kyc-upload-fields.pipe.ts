import { Injectable, type PipeTransform } from "@nestjs/common";
import { ApiError } from "../errors.js";
import { uploadFieldsSchema, type UploadFields } from "./kyc.schemas.js";

@Injectable()
export class KycUploadFieldsPipe implements PipeTransform<
  unknown,
  UploadFields
> {
  transform(value: unknown): UploadFields {
    const fields = value ?? {};
    if (
      typeof fields !== "object" ||
      Array.isArray(fields) ||
      Object.keys(fields).some(
        (name) => !["documentType", "captureId"].includes(name),
      )
    )
      throw new ApiError(400, "INVALID_UPLOAD", "Unexpected multipart field.");
    return uploadFieldsSchema.parse(fields);
  }
}
