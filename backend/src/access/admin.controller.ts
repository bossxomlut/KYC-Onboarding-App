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
  UseGuards,
} from "@nestjs/common";
import { AuthenticationGuard } from "../auth/authentication.guard.js";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { Roles, RolesGuard } from "../auth/roles.js";
import { AuthRateLimit } from "../common/auth-rate-limit.decorator.js";
import { ZodValidationPipe } from "../common/zod-validation.pipe.js";
import {
  changeRoleSchema,
  createAccountSchema,
  decideRoleSchema,
  identifierSchema,
  paginationSchema,
  requestsPaginationSchema,
  type ChangeRoleDto,
  type CreateAccountDto,
  type DecideRoleDto,
  type PaginationDto,
  type RequestsPaginationDto,
} from "./access.dto.js";
import { AccessService } from "./access.service.js";

@Controller("api/v1/admin")
@UseGuards(AuthenticationGuard, RolesGuard)
@Roles("super_admin")
export class AdminController {
  constructor(@Inject(AccessService) private readonly access: AccessService) {}

  @Get("users")
  listUsers(
    @CurrentUser() actorId: string,
    @Query(new ZodValidationPipe(paginationSchema)) pagination: PaginationDto,
  ) {
    return this.access.listUsers(actorId, pagination);
  }

  @Post("users")
  @HttpCode(201)
  @AuthRateLimit()
  createAccount(
    @CurrentUser() actorId: string,
    @Body(new ZodValidationPipe(createAccountSchema)) dto: CreateAccountDto,
  ) {
    return this.access.createAccount(actorId, dto);
  }

  @Put("users/:userId/role")
  changeRole(
    @CurrentUser() actorId: string,
    @Param("userId", new ZodValidationPipe(identifierSchema)) userId: string,
    @Body(new ZodValidationPipe(changeRoleSchema)) dto: ChangeRoleDto,
  ) {
    return this.access.changeRole(actorId, userId, dto);
  }

  @Get("role-requests")
  listRequests(
    @CurrentUser() actorId: string,
    @Query(new ZodValidationPipe(requestsPaginationSchema))
    pagination: RequestsPaginationDto,
  ) {
    return this.access.listRequests(actorId, pagination);
  }

  @Post("role-requests/:requestId/decision")
  @HttpCode(200)
  decideRequest(
    @CurrentUser() actorId: string,
    @Param("requestId", new ZodValidationPipe(identifierSchema))
    requestId: string,
    @Body(new ZodValidationPipe(decideRoleSchema)) dto: DecideRoleDto,
  ) {
    return this.access.decideRequest(actorId, requestId, dto);
  }
}
