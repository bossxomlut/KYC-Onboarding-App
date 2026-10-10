import {
  Body,
  Controller,
  Get,
  HttpCode,
  Inject,
  Param,
  Post,
  Query,
  Res,
  UseGuards,
} from "@nestjs/common";
import type { Response } from "express";
import { AuthenticationGuard } from "../auth/authentication.guard.js";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { Roles, RolesGuard } from "../auth/roles.js";
import { ZodValidationPipe } from "../common/zod-validation.pipe.js";
import { mediaKindSchema, type MediaKind } from "../kyc/kyc.schemas.js";
import {
  historyPaginationSchema,
  submissionIdSchema,
  type HistoryPagination,
} from "../kyc/kyc-history.schemas.js";
import {
  reviewDecisionSchema,
  reviewPaginationSchema,
  reviewUserIdSchema,
  type ReviewDecision,
  type ReviewPagination,
} from "./reviews.schemas.js";
import { ReviewsService } from "./reviews.service.js";

@Controller("api/v1/reviews")
@UseGuards(AuthenticationGuard, RolesGuard)
@Roles("reviewer", "super_admin")
export class ReviewsController {
  constructor(
    @Inject(ReviewsService) private readonly reviews: ReviewsService,
  ) {}

  @Get()
  queue(
    @CurrentUser() actorId: string,
    @Query(new ZodValidationPipe(reviewPaginationSchema))
    query: ReviewPagination,
  ) {
    return this.reviews.queue(actorId, query);
  }

  @Get(":userId")
  detail(
    @CurrentUser() actorId: string,
    @Param("userId", new ZodValidationPipe(reviewUserIdSchema)) userId: string,
  ) {
    return this.reviews.detail(actorId, userId);
  }

  @Get(":userId/history")
  history(
    @CurrentUser() actorId: string,
    @Param("userId", new ZodValidationPipe(reviewUserIdSchema)) userId: string,
    @Query(new ZodValidationPipe(historyPaginationSchema))
    query: HistoryPagination,
  ) {
    return this.reviews.history(actorId, userId, query);
  }

  @Get(":userId/history/:submissionId/media/:kind")
  async historyMedia(
    @CurrentUser() actorId: string,
    @Param("userId", new ZodValidationPipe(reviewUserIdSchema)) userId: string,
    @Param("submissionId", new ZodValidationPipe(submissionIdSchema))
    submissionId: string,
    @Param("kind", new ZodValidationPipe(mediaKindSchema)) kind: MediaKind,
    @Res() response: Response,
  ) {
    const media = await this.reviews.historyMedia(
      actorId,
      userId,
      submissionId,
      kind,
    );
    response
      .set("cache-control", "no-store")
      .set("content-disposition", "inline")
      .type(media.mimeType)
      .send(media.data);
  }

  @Get(":userId/media/:kind")
  async media(
    @CurrentUser() actorId: string,
    @Param("userId", new ZodValidationPipe(reviewUserIdSchema)) userId: string,
    @Param("kind", new ZodValidationPipe(mediaKindSchema)) kind: MediaKind,
    @Res() response: Response,
  ) {
    const media = await this.reviews.media(actorId, userId, kind);
    response
      .set("cache-control", "no-store")
      .set("content-disposition", "inline")
      .type(media.mimeType)
      .send(media.data);
  }

  @Post(":userId/decision")
  @HttpCode(200)
  decide(
    @CurrentUser() actorId: string,
    @Param("userId", new ZodValidationPipe(reviewUserIdSchema)) userId: string,
    @Body(new ZodValidationPipe(reviewDecisionSchema)) decision: ReviewDecision,
  ) {
    return this.reviews.decide(actorId, userId, decision);
  }
}
