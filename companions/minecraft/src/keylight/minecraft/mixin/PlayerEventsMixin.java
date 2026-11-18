package keylight.minecraft.mixin;

import keylight.minecraft.GameSignal;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.network.protocol.game.ClientboundDamageEventPacket;
import net.minecraft.client.gui.screens.LevelLoadingScreen;
import net.minecraft.network.protocol.game.ClientboundRespawnPacket;
import net.minecraft.world.level.block.Blocks;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientPacketListener.class)
abstract class PlayerEventsMixin {
    @Unique private boolean keylight$sentMotion;
    @Unique private boolean keylight$portalArrival;
    @Unique private int keylight$ticks;

    @Inject(method = "handleDamageEvent", at = @At("TAIL"))
    private void keylight$onDamage(ClientboundDamageEventPacket packet, CallbackInfo info) {
        var player = Minecraft.getInstance().player;
        if (player != null && packet.entityId() == player.getId()) {
            GameSignal.hit();
        }
    }

    // Vanilla has dispatched to the game thread here, and the old world still exists.
    @Inject(method = "handleRespawn", at = @At(value = "INVOKE",
            target = "Lnet/minecraft/network/protocol/game/ClientboundRespawnPacket;commonPlayerSpawnInfo()Lnet/minecraft/network/protocol/game/CommonPlayerSpawnInfo;",
            ordinal = 0))
    private void keylight$beforeWorldChange(ClientboundRespawnPacket packet, CallbackInfo info) {
        var player = Minecraft.getInstance().player;
        keylight$portalArrival = player != null && player.isAlive()
                && !player.level().dimension().equals(packet.commonPlayerSpawnInfo().dimension())
                && (player.portalEffectIntensity > 0 || player.level().getBlockState(player.blockPosition()).is(Blocks.NETHER_PORTAL));
    }

    @Inject(method = "tick", at = @At("TAIL"))
    private void keylight$sampleMotion(CallbackInfo info) {
        var client = Minecraft.getInstance();
        var player = client.player;
        if (player == null || player.connection != (Object) this) return;
        boolean loading = client.gui.screen() instanceof LevelLoadingScreen;
        if (keylight$portalArrival && !loading) {
            GameSignal.arrival();
            keylight$portalArrival = false;
        }
        boolean active = !loading && !client.isPaused();
        int flight = active && player.isFallFlying()
                ? 1 + (int) Math.round(254 * Math.min(1, player.getDeltaMovement().length() / 2.5)) : 0;
        int portal = active ? Math.round(255 * player.portalEffectIntensity) : 0;
        boolean moving = flight != 0 || portal != 0;
        if (moving != keylight$sentMotion || (moving && keylight$ticks % 2 == 0)) {
            GameSignal.motion(flight, portal);
        }
        keylight$sentMotion = moving;
        keylight$ticks++;
    }
}
