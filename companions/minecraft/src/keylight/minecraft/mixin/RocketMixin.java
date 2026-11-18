package keylight.minecraft.mixin;

import keylight.minecraft.GameSignal;
import net.minecraft.client.Minecraft;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.projectile.FireworkRocketEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(FireworkRocketEntity.class)
abstract class RocketMixin {
    @Shadow private LivingEntity attachedToEntity;
    @Unique private boolean keylight$reportedBoost;

    @Inject(method = "tick", at = @At("TAIL"))
    private void keylight$onBoost(CallbackInfo info) {
        if (keylight$reportedBoost || attachedToEntity == null || !attachedToEntity.level().isClientSide()) return;
        if (attachedToEntity == Minecraft.getInstance().player && attachedToEntity.isFallFlying()) {
            keylight$reportedBoost = true;
            GameSignal.boost();
        }
    }
}
