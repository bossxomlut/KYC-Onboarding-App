import { Module } from "@nestjs/common";
import { AuthController } from "./auth.controller.js";
import { AuthService } from "./auth.service.js";
import { AuthenticationGuard } from "./authentication.guard.js";
import { RolesGuard } from "./roles.js";

@Module({
  controllers: [AuthController],
  providers: [AuthService, AuthenticationGuard, RolesGuard],
  exports: [AuthService, AuthenticationGuard, RolesGuard],
})
export class AuthModule {}
