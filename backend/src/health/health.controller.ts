import { Controller, Get, Inject } from "@nestjs/common";
import type { Pool } from "pg";
import { DATABASE_POOL } from "../infrastructure/tokens.js";

@Controller()
export class HealthController {
  constructor(@Inject(DATABASE_POOL) private readonly pool: Pool) {}
  @Get("health")
  async health() {
    await this.pool.query("SELECT 1");
    return { status: "ok" };
  }
}
