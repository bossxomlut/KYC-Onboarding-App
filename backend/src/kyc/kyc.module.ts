import { Module } from "@nestjs/common";
import { MulterModule } from "@nestjs/platform-express";
import { memoryStorage } from "multer";
import { AuthModule } from "../auth/auth.module.js";
import type { Config } from "../config.js";
import { APP_CONFIG } from "../infrastructure/tokens.js";
import { KycUploadGuard } from "./kyc-upload.guard.js";
import { KycController } from "./kyc.controller.js";
import { KycService } from "./kyc.service.js";

@Module({
  imports: [
    AuthModule,
    MulterModule.registerAsync({
      inject: [APP_CONFIG],
      useFactory: (config: Config) => ({
        storage: memoryStorage(),
        limits: {
          fileSize: config.maxUploadBytes,
          files: 1,
          fields: 2,
          // Busboy emits partsLimit upon completing this count, so allow the
          // boundary after a valid three-part request. files/fields still cap
          // the accepted payload to one image plus two text fields.
          parts: 4,
        },
      }),
    }),
  ],
  controllers: [KycController],
  providers: [KycService, KycUploadGuard],
})
export class KycModule {}
