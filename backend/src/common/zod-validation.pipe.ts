import { Injectable, type PipeTransform } from "@nestjs/common";
import type { ZodType } from "zod";

/** Explicit strict schemas preserve the existing Flutter validation contract. */
@Injectable()
export class ZodValidationPipe<T> implements PipeTransform<unknown, T> {
  constructor(private readonly schema: ZodType<T>) {}
  transform(value: unknown): T {
    return this.schema.parse(value);
  }
}
