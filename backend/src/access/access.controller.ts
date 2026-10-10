import {
  Body,
  Controller,
  Get,
  HttpCode,
  Inject,
  Post,
  UseGuards,
} from "@nestjs/common";
import { AuthenticationGuard } from "../auth/authentication.guard.js";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { AuthRateLimit } from "../common/auth-rate-limit.decorator.js";
import { ZodValidationPipe } from "../common/zod-validation.pipe.js";
import { requestRoleSchema, type RequestRoleDto } from "./access.dto.js";
import { AccessService } from "./access.service.js";

@Controller("api/v1/access")
@UseGuards(AuthenticationGuard)
export class AccessController {
  constructor(@Inject(AccessService) private readonly access: AccessService) {}

  @Get("role-request")
  ownRequest(@CurrentUser() userId: string) {
    return this.access.ownRequest(userId);
  }

  @Post("role-request")
  @HttpCode(201)
  @AuthRateLimit()
  requestRole(
    @CurrentUser() userId: string,
    @Body(new ZodValidationPipe(requestRoleSchema)) dto: RequestRoleDto,
  ) {
    return this.access.requestRole(userId, dto);
  }
}
