import { Module } from "@nestjs/common";
import { AuthController } from "./auth.controller.js";
import { AuthService } from "./auth.service.js";
import { AuthenticationGuard } from "./authentication.guard.js";

@Module({
  controllers: [AuthController],
  providers: [AuthService, AuthenticationGuard],
  exports: [AuthService, AuthenticationGuard],
})
export class AuthModule {}
