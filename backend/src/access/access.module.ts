import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { AccessController } from "./access.controller.js";
import { AdminController } from "./admin.controller.js";
import { AccessService } from "./access.service.js";

@Module({
  imports: [AuthModule],
  controllers: [AccessController, AdminController],
  providers: [AccessService],
  exports: [AccessService],
})
export class AccessModule {}
