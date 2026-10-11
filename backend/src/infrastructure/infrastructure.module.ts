import {
  Global,
  Inject,
  Injectable,
  Module,
  type DynamicModule,
  type OnModuleDestroy,
  type OnModuleInit,
} from "@nestjs/common";
import type { Pool } from "pg";
import type { Config } from "../config.js";
import { startOutboxWorker, type Mailer } from "../mail.js";
import {
  APP_CONFIG,
  DATABASE_POOL,
  MAILER,
  IDENTITY_VERIFIER,
} from "./tokens.js";
import type { IdentityVerifier } from "../verification/identity-verifier.js";
import { createIdentityVerifier } from "../verification/create-identity-verifier.js";

@Injectable()
export class EmailOutboxWorker implements OnModuleInit, OnModuleDestroy {
  private stop?: () => void;
  constructor(
    @Inject(APP_CONFIG) private readonly config: Config,
    @Inject(DATABASE_POOL) private readonly pool: Pool,
    @Inject(MAILER) private readonly mailer: Mailer,
  ) {}
  onModuleInit() {
    if (this.config.nodeEnv !== "test")
      this.stop = startOutboxWorker(this.pool, this.config, this.mailer);
  }
  onModuleDestroy() {
    this.stop?.();
  }
}

/** One shared pool/config/transport; callers retain ownership of the pool. */
@Global()
@Module({})
export class InfrastructureModule {
  static register(
    config: Config,
    pool: Pool,
    mailer: Mailer,
    verifier: IdentityVerifier | null = createIdentityVerifier(config),
  ): DynamicModule {
    return {
      module: InfrastructureModule,
      providers: [
        { provide: APP_CONFIG, useValue: config },
        { provide: DATABASE_POOL, useValue: pool },
        { provide: MAILER, useValue: mailer },
        { provide: IDENTITY_VERIFIER, useValue: verifier },
        EmailOutboxWorker,
      ],
      exports: [APP_CONFIG, DATABASE_POOL, MAILER, IDENTITY_VERIFIER],
    };
  }
}
