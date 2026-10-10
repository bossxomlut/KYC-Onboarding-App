import {
  Inject,
  Injectable,
  type CanActivate,
  type ExecutionContext,
} from "@nestjs/common";
import { mediaKindSchema } from "./kyc.schemas.js";
import { KycService } from "./kyc.service.js";

@Injectable()
export class KycUploadGuard implements CanActivate {
  constructor(@Inject(KycService) private readonly kyc: KycService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<{
      userId: string;
      params: { kind?: string };
    }>();
    mediaKindSchema.parse(request.params.kind);
    await this.kyc.assertUploadEditable(request.userId);
    return true;
  }
}
