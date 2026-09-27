local custom_font = {}

-- [nzl studio] hardened font loader:
--   * init.lua writes the assets to "NZL Studio Deep/Fonts" (capital F) while the
--     original module read "NZL Studio Deep/fonts" - try both, case matters on
--     android executors
--   * every step is pcall'd and the pre-warm wait is time-boxed, so a failing
--     getcustomasset/textservice can never hang init forever
--   * last-resort fallback to the built-in Gotham so the UI always loads

local HttpService = game:GetService("HttpService");
local TextService = game:GetService("TextService");

local function get_asset(...)
    for _, path in ipairs({ ... }) do
        local ok, asset = pcall(getcustomasset, path);
        if ok and asset and #tostring(asset) > 0 then
            return asset;
        end;
    end;
    return nil;
end

local function builtin_fallback()
    local ok, font = pcall(function()
        return Font.fromEnum(Enum.Font.Gotham);
    end);

    if not ok then
        font = Font.new("rbxasset://fonts/families/GothamSSm.json");
    end;

    return {
        regular = font,
        medium = font,
        bold = font,
    };
end

function custom_font.make_lexend_font()
    local ok, result = pcall(function()
        local font_regular = get_asset("NZL Studio Deep/Fonts/Lexend.ttf", "NZL Studio Deep/fonts/Lexend.ttf");
        local font_bold = get_asset("NZL Studio Deep/Fonts/Lexend-Bold.ttf", "NZL Studio Deep/fonts/Lexend-Bold.ttf");
        local font_medium = get_asset("NZL Studio Deep/Fonts/Lexend-Medium.ttf", "NZL Studio Deep/fonts/Lexend-Medium.ttf");

        assert(font_regular and font_bold and font_medium, "could not resolve lexend ttf assets");

        pcall(function()
            makefolder("NZL Studio Deep/Fonts");
        end);
        pcall(function()
            makefolder("NZL Studio Deep/fonts");
        end);

        writefile("NZL Studio Deep/Fonts/Lexend.json", HttpService:JSONEncode({
            name = "Lexend",
            faces = {
                {
                    name = "Regular",
                    weight = 400,
                    style = "normal",
                    assetId = font_regular
                },
                {
                    name = "Medium",
                    weight = 500,
                    style = "normal",
                    assetId = font_medium
                },
                {
                    name = "Bold",
                    weight = 700,
                    style = "normal",
                    assetId = font_bold
                }
            }
        }))

        local path_asset = get_asset("NZL Studio Deep/Fonts/Lexend.json", "NZL Studio Deep/fonts/Lexend.json");
        assert(path_asset, "could not resolve lexend font json");

        local fonts = {
            regular = Font.new(
                path_asset,
                Enum.FontWeight.Regular,
                Enum.FontStyle.Normal
            ),
            medium = Font.new(
                path_asset,
                Enum.FontWeight.Medium,
                Enum.FontStyle.Normal
            ),
            bold = Font.new(
                path_asset,
                Enum.FontWeight.Bold,
                Enum.FontStyle.Normal
            )
        };

        local done = 0;
        for _, font in pairs(fonts) do
            task.spawn(function()
                pcall(function()
                    local params = Instance.new("GetTextBoundsParams")
                    params.Text = "Preload"
                    params.Font = font
                    params.Size = 16
                    TextService:GetTextBoundsAsync(params)
                    params:Destroy()
                end);
                done += 1;
            end)
        end

        local start = tick();
        repeat task.wait() until done == 3 or tick() - start > 5;

        return fonts;
    end);

    if ok and result then
        return result;
    end;

    warn(("[custom_font] lexend unavailable (%s), falling back to Gotham"):format(tostring(result)));
    return builtin_fallback();
end

return custom_font.make_lexend_font()
