import {
  Body,
  Controller,
  Get,
  HttpCode,
  Inject,
  Post,
  UseGuards,
} from "@nestjs/common";
import { ZodValidationPipe } from "../common/zod-validation.pipe.js";
import { AuthRateLimit } from "../common/auth-rate-limit.decorator.js";
import {
  EmailDto,
  LoginDto,
  RefreshDto,
  RegisterDto,
  ResetPasswordDto,
  VerifyEmailDto,
  emailSchema,
  loginSchema,
  refreshSchema,
  registerSchema,
  resetPasswordSchema,
  verifyEmailSchema,
} from "./auth.dto.js";
import { AuthService } from "./auth.service.js";
import { AuthenticationGuard } from "./authentication.guard.js";
import { CurrentUser } from "./current-user.decorator.js";

@Controller("api/v1/auth")
@AuthRateLimit()
export class AuthController {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}

  @Post("register")
  @HttpCode(201)
  register(@Body(new ZodValidationPipe(registerSchema)) dto: RegisterDto) {
    return this.auth.register(dto);
  }

  @Post("email/resend")
  @HttpCode(200)
  resendVerification(@Body(new ZodValidationPipe(emailSchema)) dto: EmailDto) {
    return this.auth.resendVerification(dto);
  }

  @Post("email/verify")
  @HttpCode(200)
  verifyEmail(
    @Body(new ZodValidationPipe(verifyEmailSchema)) dto: VerifyEmailDto,
  ) {
    return this.auth.verifyEmail(dto);
  }

  @Post("login")
  @HttpCode(200)
  login(@Body(new ZodValidationPipe(loginSchema)) dto: LoginDto) {
    return this.auth.login(dto);
  }

  @Post("refresh")
  @HttpCode(200)
  refresh(@Body(new ZodValidationPipe(refreshSchema)) dto: RefreshDto) {
    return this.auth.refresh(dto);
  }

  @Post("logout")
  @HttpCode(200)
  logout(@Body(new ZodValidationPipe(refreshSchema)) dto: RefreshDto) {
    return this.auth.logout(dto);
  }

  @Get("me")
  @UseGuards(AuthenticationGuard)
  currentUser(@CurrentUser() userId: string) {
    return this.auth.currentUser(userId);
  }

  @Post("password/forgot")
  @HttpCode(200)
  forgotPassword(@Body(new ZodValidationPipe(emailSchema)) dto: EmailDto) {
    return this.auth.forgotPassword(dto);
  }

  @Post("password/reset")
  @HttpCode(200)
  resetPassword(
    @Body(new ZodValidationPipe(resetPasswordSchema)) dto: ResetPasswordDto,
  ) {
    return this.auth.resetPassword(dto);
  }
}
