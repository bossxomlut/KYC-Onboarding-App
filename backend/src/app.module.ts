import { Module, type DynamicModule } from "@nestjs/common";
import { APP_FILTER, APP_GUARD } from "@nestjs/core";
import type { Pool } from "pg";
import type { Config } from "./config.js";
import type { Mailer } from "./mail.js";
import { InfrastructureModule } from "./infrastructure/infrastructure.module.js";
import { AuthModule } from "./auth/auth.module.js";
import { KycModule } from "./kyc/kyc.module.js";
import { AccessModule } from "./access/access.module.js";
import { ReviewsModule } from "./reviews/reviews.module.js";
import { HealthController } from "./health/health.controller.js";
import { ApiExceptionFilter } from "./common/api-exception.filter.js";
import { RateLimitGuard } from "./common/rate-limit.guard.js";
import type { IdentityVerifier } from "./verification/identity-verifier.js";

@Module({})
export class AppModule {
  static register(
    config: Config,
    pool: Pool,
    mailer: Mailer,
    verifier?: IdentityVerifier | null,
  ): DynamicModule {
    return {
      module: AppModule,
      imports: [
        InfrastructureModule.register(config, pool, mailer, verifier),
        AuthModule,
        KycModule,
        AccessModule,
        ReviewsModule,
      ],
      controllers: [HealthController],
      providers: [
        { provide: APP_FILTER, useClass: ApiExceptionFilter },
        { provide: APP_GUARD, useClass: RateLimitGuard },
      ],
    };
  }
}
