import {
  Inject,
  Injectable,
  type CanActivate,
  type ExecutionContext,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Request, Response } from "express";
import type { Config } from "../config.js";
import { ApiError } from "../errors.js";
import { APP_CONFIG } from "../infrastructure/tokens.js";
import { AUTH_RATE_LIMIT } from "./auth-rate-limit.decorator.js";

interface Counter {
  count: number;
  resetsAt: number;
}

/** Local, per-route/per-IP limits. Production replicas need shared storage. */
@Injectable()
export class RateLimitGuard implements CanActivate {
  private readonly routes = new WeakMap<Function, Map<string, Counter>>();
  constructor(
    @Inject(APP_CONFIG) private readonly config: Config,
    @Inject(Reflector) private readonly reflector: Reflector,
  ) {}
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const response = context.switchToHttp().getResponse<Response>();
    const route = context.getHandler();
    let counters = this.routes.get(route);
    if (!counters) {
      counters = new Map();
      this.routes.set(route, counters);
    }
    const now = Date.now();
    for (const [ip, value] of counters)
      if (value.resetsAt <= now) counters.delete(ip);
    const ip = request.ip ?? request.socket.remoteAddress ?? "unknown";
    const counter = counters.get(ip) ?? { count: 0, resetsAt: now + 60_000 };
    const limit =
      request.method === "POST" &&
      this.reflector.getAllAndOverride<boolean>(AUTH_RATE_LIMIT, [
        route,
        context.getClass(),
      ])
        ? this.config.rateLimitMax
        : 120;
    counters.set(ip, counter);
    counter.count++;
    response.setHeader("x-ratelimit-limit", limit);
    response.setHeader(
      "x-ratelimit-remaining",
      Math.max(0, limit - counter.count),
    );
    if (counter.count > limit) {
      response.setHeader(
        "retry-after",
        Math.ceil((counter.resetsAt - now) / 1000),
      );
      throw new ApiError(
        429,
        "RATE_LIMITED",
        "Too many attempts. Please try again shortly.",
      );
    }
    return true;
  }
}
