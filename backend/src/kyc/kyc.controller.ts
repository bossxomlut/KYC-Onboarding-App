import {
  Body,
  Controller,
  Get,
  HttpCode,
  Inject,
  Param,
  Post,
  Put,
  Query,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import type { Response } from "express";
import { AuthenticationGuard } from "../auth/authentication.guard.js";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { ZodValidationPipe } from "../common/zod-validation.pipe.js";
import {
  mediaKindSchema,
  personalDetailsSchema,
  type MediaKind,
  type PersonalDetails,
  type UploadFields,
} from "./kyc.schemas.js";
import { KycService } from "./kyc.service.js";
import { KycUploadGuard } from "./kyc-upload.guard.js";
import { KycUploadFieldsPipe } from "./kyc-upload-fields.pipe.js";
import {
  historyPaginationSchema,
  submissionIdSchema,
  type HistoryPagination,
} from "./kyc-history.schemas.js";

@Controller("api/v1/kyc")
@UseGuards(AuthenticationGuard)
export class KycController {
  constructor(@Inject(KycService) private readonly kyc: KycService) {}

  @Get()
  profile(@CurrentUser() userId: string) {
    return this.kyc.profile(userId);
  }

  @Get("history")
  history(
    @CurrentUser() userId: string,
    @Query(new ZodValidationPipe(historyPaginationSchema))
    query: HistoryPagination,
  ) {
    return this.kyc.history(userId, query);
  }

  @Get("history/:submissionId/media/:kind")
  async historyMedia(
    @CurrentUser() userId: string,
    @Param("submissionId", new ZodValidationPipe(submissionIdSchema))
    submissionId: string,
    @Param("kind", new ZodValidationPipe(mediaKindSchema)) kind: MediaKind,
    @Res() response: Response,
  ) {
    const media = await this.kyc.historyMedia(userId, submissionId, kind);
    response
      .set("cache-control", "no-store")
      .set("content-disposition", "inline")
      .type(media.mimeType)
      .send(media.data);
  }

  @Put("personal-details")
  savePersonalDetails(
    @CurrentUser() userId: string,
    @Body(new ZodValidationPipe(personalDetailsSchema))
    details: PersonalDetails,
  ) {
    return this.kyc.savePersonalDetails(userId, details);
  }

  @Post("media/:kind")
  @HttpCode(200)
  @UseGuards(KycUploadGuard)
  @UseInterceptors(FileInterceptor("file"))
  uploadMedia(
    @CurrentUser() userId: string,
    @Param("kind", new ZodValidationPipe(mediaKindSchema)) kind: MediaKind,
    @Body(new KycUploadFieldsPipe()) fields: UploadFields,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.kyc.uploadMedia(
      userId,
      kind,
      fields,
      file ? { data: file.buffer, mimeType: file.mimetype } : undefined,
    );
  }

  @Get("media/:kind")
  async readMedia(
    @CurrentUser() userId: string,
    @Param("kind", new ZodValidationPipe(mediaKindSchema)) kind: MediaKind,
    @Res() response: Response,
  ) {
    const media = await this.kyc.readMedia(userId, kind);
    response
      .set("cache-control", "no-store")
      .set("content-disposition", "inline")
      .type(media.mimeType)
      .send(media.data);
  }

  @Post("submit")
  @HttpCode(200)
  submit(@CurrentUser() userId: string) {
    return this.kyc.submit(userId);
  }

  @Post("resubmit")
  @HttpCode(200)
  resubmit(@CurrentUser() userId: string) {
    return this.kyc.resubmit(userId);
  }
}
