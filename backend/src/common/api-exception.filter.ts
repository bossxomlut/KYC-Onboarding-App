import {
  Catch,
  HttpException,
  type ArgumentsHost,
  type ExceptionFilter,
} from "@nestjs/common";
import type { Request, Response } from "express";
import { randomUUID } from "node:crypto";
import { ZodError } from "zod";
import { ApiError } from "../errors.js";

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost) {
    const http = host.switchToHttp();
    const request = http.getRequest<Request & { requestId?: string }>();
    const reply = http.getResponse<Response>();
    let status = 500;
    let code = "INTERNAL_ERROR";
    let message = "Unable to complete the request. Please try again.";
    if (error instanceof ApiError) {
      ({ status, code, message } = error);
    } else if (error instanceof ZodError) {
      status = 400;
      code = "VALIDATION_ERROR";
      message = error.issues
        .map(
          (issue) => `${issue.path.join(".") || "request"}: ${issue.message}`,
        )
        .join("; ");
    } else {
      const exception = (
        typeof error === "object" && error !== null ? error : {}
      ) as {
        status?: number;
        statusCode?: number;
        message?: string;
        code?: string;
        type?: string;
      };
      const httpStatus =
        error instanceof HttpException
          ? error.getStatus()
          : (exception.status ?? exception.statusCode);
      const text = exception.message ?? "";
      const upload =
        request.method === "POST" &&
        request.path.startsWith("/api/v1/kyc/media/");
      const uploadLimit =
        upload &&
        (/^LIMIT_(FILE_SIZE|FILE_COUNT|PART_COUNT|FIELD_COUNT|FIELD_VALUE|FIELD_KEY)$/.test(
          exception.code ?? "",
        ) ||
          /file too large|too many (files|fields|parts)|field (value|name) too long/i.test(
            text,
          ));
      if (uploadLimit || (upload && httpStatus === 413)) {
        status = 413;
        code = "UPLOAD_TOO_LARGE";
        message =
          "Upload one image within the configured size and multipart limits.";
      } else if (httpStatus === 413) {
        status = 413;
        code = "REQUEST_TOO_LARGE";
        message = "The request is too large.";
      } else if (httpStatus === 404) {
        status = 404;
        code = "NOT_FOUND";
        message = "Endpoint not found.";
      } else if (httpStatus === 429) {
        status = 429;
        code = "RATE_LIMITED";
        message = "Too many attempts. Please try again shortly.";
      } else if (httpStatus === 400 || httpStatus === 415) {
        status = 400;
        code = upload ? "INVALID_UPLOAD" : "INVALID_REQUEST";
        message = upload
          ? "Upload one image using the file field and supported multipart fields."
          : "The request format is invalid.";
      }
    }
    reply.status(status).json({
      error: { code, message, requestId: request.requestId ?? randomUUID() },
    });
  }
}
