-- Item relevance aggregation for ElvUI M+ Loot.

local E = ElvUI and unpack(ElvUI)
local MPL = E and E:GetModule("ElvUI_MythicPlusLoot", true)

if not MPL then return end

function MPL:GetItemRelevance(itemLink)
    if not itemLink or not self.GetKeystoneLootFavoriteTier then
        return nil
    end

    local ok, tier = pcall(self.GetKeystoneLootFavoriteTier, self, itemLink)
    tier = ok and tonumber(tier) or nil
    if not tier or tier <= 0 then
        return nil
    end

    return {
        keystoneLootTier = tier,
    }
end
